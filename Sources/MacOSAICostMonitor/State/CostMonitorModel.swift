import Combine
import Foundation

public enum MonitorState: Sendable, Equatable {
    case notConfigured
    case loading(previous: DailyCost?)
    case loaded(DailyCost, fetchedAt: Date, stale: Bool)
    case noData(date: String, fetchedAt: Date?, previous: DailyCost?)
    case failed(message: String, previous: DailyCost?, staleSince: Date?)

    public var dailyCost: DailyCost? {
        switch self {
        case .loaded(let cost, _, _): return cost
        case .loading(let previous): return previous
        case .noData(_, _, let previous): return previous
        case .failed(_, let previous, _): return previous
        case .notConfigured: return nil
        }
    }

    public var statusMessage: String? {
        switch self {
        case .notConfigured:
            return "Add an OpenRouter management key in Settings."
        case .loading(_):
            return "Refreshing OpenRouter usage…"
        case .loaded(_, _, let stale):
            return stale ? "Showing a stale value." : nil
        case .noData(_, _, _):
            return "OpenRouter has not published activity for this completed UTC day yet."
        case .failed(let message, _, _):
            return message
        }
    }
}

public protocol UTCDateProviding: Sendable {
    func currentDateString() -> String
}

/// Supplies the latest completed UTC calendar day because OpenRouter's activity
/// endpoint does not guarantee data for the in-progress UTC day.
public struct SystemUTCDateProvider: UTCDateProviding {
    private let now: @Sendable () -> Date

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    public func currentDateString() -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let completedDate = calendar.date(byAdding: .day, value: -1, to: now()) ?? now()
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: completedDate)
    }
}

@MainActor
public final class CostMonitorModel: ObservableObject {
    @Published public private(set) var state: MonitorState = .notConfigured
    @Published public private(set) var lastUpdated: Date?

    private let provider: any UsageProvider
    private let secretStore: any SecretStore
    private let cache: any CostCache
    private let dateProvider: any UTCDateProviding
    private let now: @Sendable () -> Date
    public let preferences: ReportingPreferences
    public let logStore: AppLogStore
    private var refreshTask: Task<Bool, Never>?
    private var schedulerTask: Task<Void, Never>?
    private var managementKey: String?
    private var didLoadManagementKey = false
    private var managementKeyErrorMessage: String?

    public init(
        provider: any UsageProvider,
        secretStore: any SecretStore,
        cache: any CostCache,
        dateProvider: any UTCDateProviding = SystemUTCDateProvider(),
        now: @escaping @Sendable () -> Date = { Date() },
        preferences: ReportingPreferences = ReportingPreferences(),
        logStore: AppLogStore = AppLogStore()
    ) {
        self.provider = provider
        self.secretStore = secretStore
        self.cache = cache
        self.dateProvider = dateProvider
        self.now = now
        self.preferences = preferences
        self.logStore = logStore
        logStore.info("Monitor initialized")

        if let cached = cache.load() {
            lastUpdated = cached.fetchedAt
            if cached.hasActivity {
                state = .loaded(cached.cost, fetchedAt: cached.fetchedAt, stale: true)
            } else {
                state = .noData(date: cached.cost.date, fetchedAt: cached.fetchedAt, previous: cached.previousCost)
            }
        }
    }

    @discardableResult
    public func refresh() async -> Bool {
        if let refreshTask {
            return await refreshTask.value
        }
        logStore.debug("Refresh requested")
        let task = Task { @MainActor [weak self] in
            await self?.performRefresh() ?? false
        }
        refreshTask = task
        let result = await task.value
        refreshTask = nil
        return result
    }

    public func saveManagementKey(_ key: String) async throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try secretStore.save(trimmed)
        managementKey = trimmed
        didLoadManagementKey = true
        managementKeyErrorMessage = nil
        state = .loading(previous: state.dailyCost)
        _ = await refresh()
    }

    public func deleteManagementKey() throws {
        try secretStore.delete()
        managementKey = nil
        didLoadManagementKey = true
        managementKeyErrorMessage = nil
        state = .notConfigured
        lastUpdated = nil
    }

    public func startPolling(interval: TimeInterval = 300) {
        guard schedulerTask == nil else { return }
        let scheduler = RefreshScheduler()
        schedulerTask = scheduler.start(interval: interval, immediate: false) { [weak self] in
            guard let self else { return true }
            return await self.refresh()
        }
    }

    public func stopPolling() {
        schedulerTask?.cancel()
        schedulerTask = nil
    }

    public func applyPreferenceChanges() {
        if schedulerTask != nil {
            stopPolling()
            startPolling(interval: preferences.refreshInterval)
        }
        Task { _ = await refresh() }
    }

    private func performRefresh() async -> Bool {
        let previous = state.dailyCost
        if !didLoadManagementKey {
            logStore.debug("Reading management key from Keychain")
            do {
                managementKey = try secretStore.read()
                didLoadManagementKey = true
                managementKeyErrorMessage = nil
                logStore.info(managementKey == nil ? "No management key configured" : "Management key loaded")
            } catch let error as KeychainStoreError {
                managementKeyErrorMessage = error.userMessage
                logStore.error("Keychain read failed: \(error.userMessage)")
            } catch {
                managementKeyErrorMessage = "The OpenRouter key could not be read from Keychain."
                logStore.error("Keychain read failed")
            }
        }

        if let managementKeyErrorMessage {
            state = .failed(message: managementKeyErrorMessage, previous: previous, staleSince: lastUpdated ?? now())
            return false
        }

        guard let key = managementKey, !key.isEmpty else {
            state = .notConfigured
            return true
        }

        state = .loading(previous: previous)
        logStore.info("Fetching OpenRouter activity window")
        do {
            let items = try await provider.recentActivity(apiKey: key, captureRawResponse: preferences.captureRawHTTPResponses)
            logStore.info("Received \(items.count) activity rows")
            let latestDate = items.map(\.date).max() ?? dateProvider.currentDateString()
            let date = latestDate
            let selectedRange = preferences.timeRange
            let referenceDate = Self.utcDate(from: date) ?? Date()
            let range = selectedRange.dayRange(reference: referenceDate)
            let matchingItems: [ActivityItem]
            if selectedRange == .latestAvailableDay {
                matchingItems = items.filter { $0.date == date }
            } else {
                let referenceOffset = Self.utcDayOffset(from: referenceDate)
                matchingItems = items.filter {
                    guard let itemDate = Self.utcDate(from: $0.date) else { return false }
                    let offset = Self.utcDayOffset(from: itemDate) - referenceOffset
                    return offset <= range.upperBound && offset >= range.lowerBound
                }
            }
            let reportDate = selectedRange == .latestAvailableDay ? date : selectedRange.reportLabel
            let cost = selectedRange == .latestAvailableDay
                ? ActivityAggregator.aggregate(matchingItems, for: reportDate)
                : ActivityAggregator.aggregateAll(matchingItems, reportDate: reportDate)
            logStore.info("Report \(reportDate): \(cost.requests) requests, \(cost.promptTokens + cost.completionTokens + cost.reasoningTokens) tokens")
            let fetchedAt = now()
            lastUpdated = fetchedAt

            if matchingItems.isEmpty {
                state = .noData(date: reportDate, fetchedAt: fetchedAt, previous: previous)
                do {
                    try cache.save(CachedUsage(cost: cost, fetchedAt: fetchedAt, hasActivity: false, previousCost: previous))
                    logStore.debug("Cached no-data result")
                } catch {
                    // A cache failure must not hide a valid no-data response.
                    logStore.warning("Cache write failed for no-data result")
                }
                return true
            }

            // Publish the live result before persistence. Cache failures are non-fatal.
            state = .loaded(cost, fetchedAt: fetchedAt, stale: false)
            do {
                try cache.save(CachedUsage(cost: cost, fetchedAt: fetchedAt, hasActivity: true))
                logStore.debug("Cached live result")
            } catch {
                // The next scheduled refresh can try persistence again.
                logStore.warning("Cache write failed for live result")
            }
            return true
        } catch is CancellationError {
            return false
        } catch let error as OpenRouterClientError {
            logStore.error("OpenRouter request failed: \(error.userMessage)")
            state = .failed(message: error.userMessage, previous: previous, staleSince: lastUpdated ?? now())
            return false
        } catch {
            logStore.error("OpenRouter request failed: network or decoding error")
            state = .failed(
                message: "OpenRouter could not be reached. Showing the last known value.",
                previous: previous,
                staleSince: lastUpdated ?? now()
            )
            return false
        }
    }
}

public struct FixedUTCDateProvider: UTCDateProviding {
    public let date: String
    public init(date: String) { self.date = date }
    public func currentDateString() -> String { date }
}

public extension CostMonitorModel {
    static func utcDate(from string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)
    }

    static func utcDayOffset(from date: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = calendar.startOfDay(for: date)
        let reference = Date(timeIntervalSince1970: 0)
        return calendar.dateComponents([.day], from: reference, to: start).day ?? 0
    }
}
