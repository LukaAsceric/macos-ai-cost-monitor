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
            return "OpenRouter has not published activity for this UTC day yet."
        case .failed(let message, _, _):
            return message
        }
    }
}

public protocol UTCDateProviding: Sendable {
    func currentDateString() -> String
}

public struct SystemUTCDateProvider: UTCDateProviding {
    public init() {}

    public func currentDateString() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
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
    private var refreshTask: Task<Bool, Never>?
    private var schedulerTask: Task<Void, Never>?

    public init(
        provider: any UsageProvider,
        secretStore: any SecretStore,
        cache: any CostCache,
        dateProvider: any UTCDateProviding = SystemUTCDateProvider(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.provider = provider
        self.secretStore = secretStore
        self.cache = cache
        self.dateProvider = dateProvider
        self.now = now

        if let cached = cache.load(), cached.cost.date == dateProvider.currentDateString() {
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
        state = .loading(previous: state.dailyCost)
        _ = await refresh()
    }

    public func deleteManagementKey() throws {
        try secretStore.delete()
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

    deinit {
        refreshTask?.cancel()
        schedulerTask?.cancel()
    }

    private func performRefresh() async -> Bool {
        let date = dateProvider.currentDateString()
        let previous = state.dailyCost.flatMap { $0.date == date ? $0 : nil }
        let key: String?

        do {
            key = try secretStore.read()
        } catch let error as KeychainStoreError {
            state = .failed(message: error.userMessage, previous: previous, staleSince: lastUpdated ?? now())
            return false
        } catch {
            state = .failed(
                message: "The OpenRouter key could not be read from Keychain.",
                previous: previous,
                staleSince: lastUpdated ?? now()
            )
            return false
        }

        guard let key, !key.isEmpty else {
            state = .notConfigured
            return true
        }

        state = .loading(previous: previous)
        do {
            let items = try await provider.activity(for: date, apiKey: key)
            let matchingItems = items.filter { $0.date == date }
            let cost = ActivityAggregator.aggregate(matchingItems, for: date)
            let fetchedAt = now()
            lastUpdated = fetchedAt

            if matchingItems.isEmpty {
                state = .noData(date: date, fetchedAt: fetchedAt, previous: previous)
                do {
                    try cache.save(CachedUsage(cost: cost, fetchedAt: fetchedAt, hasActivity: false, previousCost: previous))
                } catch {
                    // A cache failure must not hide a valid no-data response.
                }
                return true
            }

            // Publish the live result before persistence. Cache failures are non-fatal.
            state = .loaded(cost, fetchedAt: fetchedAt, stale: false)
            do {
                try cache.save(CachedUsage(cost: cost, fetchedAt: fetchedAt, hasActivity: true))
            } catch {
                // The next scheduled refresh can try persistence again.
            }
            return true
        } catch is CancellationError {
            return false
        } catch let error as OpenRouterClientError {
            state = .failed(message: error.userMessage, previous: previous, staleSince: lastUpdated ?? now())
            return false
        } catch {
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
