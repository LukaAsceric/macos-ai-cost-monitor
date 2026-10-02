import Combine
import Foundation

public enum ManagementKeyStatus: String, Sendable, Equatable {
    case unknown
    case missing
    case configured
    case unavailable

    public var title: String {
        switch self {
        case .unknown: return "Not checked"
        case .missing: return "Not configured"
        case .configured: return "Configured"
        case .unavailable: return "Unavailable"
        }
    }

    public var systemImage: String {
        switch self {
        case .unknown: return "questionmark.circle"
        case .missing: return "key.slash"
        case .configured: return "checkmark.shield"
        case .unavailable: return "exclamationmark.triangle"
        }
    }
}

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
            return "Add a credential in Settings → Provider."
        case .loading(_):
            return "Refreshing usage…"
        case .loaded(_, _, let stale):
            return stale ? "Showing a stale value." : nil
        case .noData(_, _, _):
            return "The provider has not published activity for this completed UTC day yet."
        case .failed(let message, _, _):
            return message
        }
    }
}

public protocol UTCDateProviding: Sendable {
    func currentDateString() -> String
}

/// The usage client and secret storage one provider runs against.
public struct ProviderEnvironment: Sendable {
    public let usage: any UsageProvider
    public let secrets: any SecretStore

    public init(usage: any UsageProvider, secrets: any SecretStore) {
        self.usage = usage
        self.secrets = secrets
    }
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
    @Published public private(set) var managementKeyStatus: ManagementKeyStatus = .unknown
    @Published public private(set) var lastRefreshSucceeded: Bool? = nil
    @Published public private(set) var remainingCredits: Decimal?
    @Published public private(set) var sessionCount: Int?
    /// Per-provider problems from the last aggregated refresh (for example one
    /// provider's expired credential while the others still reported data).
    @Published public private(set) var providerWarnings: [String] = []

    /// Provider name shown in the menu-bar dialog and tooltips. Aggregation
    /// reports every configured provider as one combined service.
    public var displayProviderTitle: String {
        preferences.aggregateProviders ? "All providers" : preferences.provider.title
    }

    public var currentReportTitle: String {
        preferences.timeRange.reportLabel
    }

    public var connectionStatusTitle: String {
        switch state {
        case .failed: return "Needs attention"
        case .loading: return "Refreshing"
        case .notConfigured: return "Not configured"
        case .loaded, .noData: return "Connected"
        }
    }
    @Published public private(set) var series: [CostSeriesPoint] = []
    @Published public private(set) var budgetExceeded = false
    @Published public private(set) var lastLogExportURL: URL?

    private let environmentByProvider: (ProviderOption) -> ProviderEnvironment
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
    private var loadedProvider: ProviderOption?

    public init(
        provider: any UsageProvider,
        secretStore: any SecretStore,
        cache: any CostCache,
        dateProvider: any UTCDateProviding = SystemUTCDateProvider(),
        now: @escaping @Sendable () -> Date = { Date() },
        preferences: ReportingPreferences = ReportingPreferences(),
        logStore: AppLogStore = AppLogStore(),
        environmentByProvider: ((ProviderOption) -> ProviderEnvironment)? = nil
    ) {
        let defaultEnvironment = ProviderEnvironment(usage: provider, secrets: secretStore)
        self.environmentByProvider = environmentByProvider ?? { _ in defaultEnvironment }
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
        try activeEnvironment.secrets.save(trimmed)
        loadedProvider = preferences.provider
        managementKey = trimmed
        didLoadManagementKey = true
        managementKeyErrorMessage = nil
        state = .loading(previous: state.dailyCost)
        _ = await refresh()
    }

    public func deleteManagementKey() throws {
        try activeEnvironment.secrets.delete()
        loadedProvider = preferences.provider
        managementKey = nil
        didLoadManagementKey = true
        managementKeyErrorMessage = nil
        state = .notConfigured
        lastUpdated = nil
    }

    /// Saves a credential for one specific provider so aggregation mode can be
    /// configured without switching the active provider back and forth.
    public func saveManagementKey(_ key: String, for provider: ProviderOption) async throws {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try environmentByProvider(provider).secrets.save(trimmed)
        if provider == preferences.provider {
            loadedProvider = provider
            managementKey = trimmed
            didLoadManagementKey = true
        }
    }

    public func deleteManagementKey(for provider: ProviderOption) throws {
        try environmentByProvider(provider).secrets.delete()
        if provider == preferences.provider {
            loadedProvider = provider
            managementKey = nil
            didLoadManagementKey = true
            managementKeyErrorMessage = nil
            state = .notConfigured
            lastUpdated = nil
        }
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

    private var activeEnvironment: ProviderEnvironment {
        environmentByProvider(preferences.provider)
    }

    private func performRefresh() async -> Bool {
        let previous = state.dailyCost
        if preferences.aggregateProviders {
            return await performAggregatedRefresh(previous: previous)
        }
        providerWarnings = []
        if loadedProvider != preferences.provider {
            // Credentials are stored per provider; switching providers must re-read
            // the other provider's secret instead of reusing the cached one.
            loadedProvider = preferences.provider
            didLoadManagementKey = false
            managementKey = nil
            managementKeyErrorMessage = nil
        }
        if !didLoadManagementKey {
            logStore.debug("Reading management key from Keychain")
            do {
                managementKey = try activeEnvironment.secrets.read()
                didLoadManagementKey = true
                managementKeyErrorMessage = nil
                logStore.info(managementKey == nil ? "No management key configured" : "Management key loaded")
            } catch let error as KeychainStoreError {
                managementKeyErrorMessage = error.userMessage
                logStore.error("Keychain read failed: \(error.userMessage)")
            } catch {
                managementKeyErrorMessage = "The \(preferences.provider.title) credential could not be read from Keychain."
                logStore.error("Keychain read failed")
            }
        }

        if let managementKeyErrorMessage {
            managementKeyStatus = .unavailable
            lastRefreshSucceeded = false
            state = .failed(message: managementKeyErrorMessage, previous: previous, staleSince: lastUpdated ?? now())
            return false
        }

        guard let key = managementKey, !key.isEmpty else {
            managementKeyStatus = .missing
            lastRefreshSucceeded = nil
            state = .notConfigured
            return true
        }

        managementKeyStatus = .configured
        lastRefreshSucceeded = nil
        state = .loading(previous: previous)
        logStore.info("Querying \(preferences.provider.title) analytics")
        do {
            let query = AnalyticsQuery.make(
                range: preferences.timeRange,
                now: now(),
                timeZone: preferences.displayTimeZone,
                customStart: preferences.customStart,
                customEnd: preferences.customEnd
            )
            let granularity = query.granularity?.rawValue ?? "aggregate"
            logStore.info("Analytics \(preferences.timeRange.title) \(granularity) \(query.timeRange.start) → \(query.timeRange.end)")
            let result = try await activeEnvironment.usage.queryAnalytics(
                query,
                apiKey: key,
                captureRawResponse: preferences.captureRawHTTPResponses
            )
            logStore.info("Received \(result.rows.count) analytics rows")
            await refreshAccountSummary(apiKey: key)
            let reportDate = preferences.timeRange.reportLabel
            let cost = result.dailyCost(label: reportDate)
            series = result.series
            if result.truncated {
                logStore.warning("Analytics result was truncated; totals may be incomplete")
            }
            let fetchedAt = now()
            lastUpdated = fetchedAt
            evaluateBudget(for: cost)

            lastRefreshSucceeded = true
            if result.rows.isEmpty {
                state = .noData(date: reportDate, fetchedAt: fetchedAt, previous: previous)
                do {
                    try cache.save(CachedUsage(cost: cost, fetchedAt: fetchedAt, hasActivity: false, previousCost: previous))
                    logStore.debug("Cached no-data result")
                } catch {
                    logStore.warning("Cache write failed for no-data result")
                }
                return true
            }

            state = .loaded(cost, fetchedAt: fetchedAt, stale: false)
            do {
                try cache.save(CachedUsage(cost: cost, fetchedAt: fetchedAt, hasActivity: true))
                logStore.debug("Cached live result")
            } catch {
                logStore.warning("Cache write failed for live result")
            }
            return true
        } catch is CancellationError {
            return false
        } catch let error as OpenRouterClientError {
            lastRefreshSucceeded = false
            logStore.error("\(preferences.provider.title) request failed: \(error.userMessage)")
            state = .failed(message: error.userMessage, previous: previous, staleSince: lastUpdated ?? now())
            return false
        } catch let error as PrimaLabsClientError {
            lastRefreshSucceeded = false
            logStore.error("\(preferences.provider.title) request failed: \(error.userMessage)")
            state = .failed(message: error.userMessage, previous: previous, staleSince: lastUpdated ?? now())
            return false
        } catch {
            lastRefreshSucceeded = false
            logStore.error("\(preferences.provider.title) request failed: network or decoding error")
            state = .failed(
                message: "The provider could not be reached. Showing the last known value.",
                previous: previous,
                staleSince: lastUpdated ?? now()
            )
            return false
        }
    }

    private struct ProviderTarget {
        let provider: ProviderOption
        let environment: ProviderEnvironment
        let credential: String
    }

    /// Aggregation mode: sum usage, credits, and sessions across every provider
    /// that has a saved credential. Providers without a credential are skipped;
    /// a provider that fails contributes a warning instead of failing the whole
    /// refresh, so one expired credential does not blank out the other totals.
    private func performAggregatedRefresh(previous: DailyCost?) async -> Bool {
        var targets: [ProviderTarget] = []
        var warnings: [String] = []
        for provider in ProviderOption.allCases where provider.isEnabled {
            let environment = environmentByProvider(provider)
            do {
                if let credential = try environment.secrets.read()?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !credential.isEmpty {
                    targets.append(ProviderTarget(provider: provider, environment: environment, credential: credential))
                }
            } catch {
                warnings.append("\(provider.title): The saved credential could not be read from Keychain.")
            }
        }

        if targets.isEmpty {
            providerWarnings = warnings
            managementKeyStatus = .missing
            lastRefreshSucceeded = nil
            state = .notConfigured
            return true
        }

        managementKeyStatus = .configured
        lastRefreshSucceeded = nil
        state = .loading(previous: previous)
        let query = AnalyticsQuery.make(
            range: preferences.timeRange,
            now: now(),
            timeZone: preferences.displayTimeZone,
            customStart: preferences.customStart,
            customEnd: preferences.customEnd
        )
        logStore.info("Querying \(targets.count) provider(s) in aggregation mode")

        var rows: [AnalyticsRow] = []
        var succeeded = 0
        var creditsRemaining = Decimal.zero
        var creditsAvailable = false
        var sessions = 0
        var sessionsAvailable = false
        for target in targets {
            do {
                let result = try await target.environment.usage.queryAnalytics(
                    query,
                    apiKey: target.credential,
                    captureRawResponse: preferences.captureRawHTTPResponses
                )
                rows.append(contentsOf: result.rows)
                succeeded += 1
            } catch is CancellationError {
                return false
            } catch {
                warnings.append("\(target.provider.title): \(providerErrorMessage(error))")
            }
            do {
                let credits = try await target.environment.usage.credits(
                    apiKey: target.credential,
                    captureRawResponse: preferences.captureRawHTTPResponses
                )
                creditsRemaining += max(credits.totalCredits - credits.totalUsage, .zero)
                creditsAvailable = true
            } catch {
                logStore.warning("Credits summary unavailable for \(target.provider.title)")
            }
            do {
                let sessionQuery = AnalyticsQuery.sessionCount(
                    range: preferences.timeRange,
                    now: now(),
                    timeZone: preferences.displayTimeZone,
                    customStart: preferences.customStart,
                    customEnd: preferences.customEnd
                )
                let result = try await target.environment.usage.queryAnalytics(
                    sessionQuery,
                    apiKey: target.credential,
                    captureRawResponse: preferences.captureRawHTTPResponses
                )
                sessions += result.sessionCount
                sessionsAvailable = true
            } catch {
                logStore.warning("Session summary unavailable for \(target.provider.title)")
            }
        }
        providerWarnings = warnings

        if succeeded == 0 {
            let message = warnings.first ?? "The providers could not be reached. Showing the last known value."
            lastRefreshSucceeded = false
            logStore.error("Aggregated refresh failed: \(message)")
            state = .failed(message: message, previous: previous, staleSince: lastUpdated ?? now())
            return false
        }

        let reportDate = preferences.timeRange.reportLabel
        let merged = AnalyticsQueryResult(rows: rows, truncated: false)
        let cost = merged.dailyCost(label: reportDate)
        series = merged.series
        remainingCredits = creditsAvailable ? creditsRemaining : nil
        sessionCount = sessionsAvailable ? sessions : nil
        let fetchedAt = now()
        lastUpdated = fetchedAt
        evaluateBudget(for: cost)
        lastRefreshSucceeded = true
        logStore.info("Received \(rows.count) aggregated analytics rows from \(succeeded) provider(s)")

        if rows.isEmpty {
            state = .noData(date: reportDate, fetchedAt: fetchedAt, previous: previous)
            do {
                try cache.save(CachedUsage(cost: cost, fetchedAt: fetchedAt, hasActivity: false, previousCost: previous))
            } catch {
                logStore.warning("Cache write failed for no-data result")
            }
            return true
        }

        state = .loaded(cost, fetchedAt: fetchedAt, stale: false)
        do {
            try cache.save(CachedUsage(cost: cost, fetchedAt: fetchedAt, hasActivity: true))
        } catch {
            logStore.warning("Cache write failed for live result")
        }
        return true
    }

    private func providerErrorMessage(_ error: Error) -> String {
        if let error = error as? OpenRouterClientError { return error.userMessage }
        if let error = error as? PrimaLabsClientError { return error.userMessage }
        return "The provider could not be reached. Showing the last known value."
    }

    private func refreshAccountSummary(apiKey: String) async {
        do {
            let credits = try await activeEnvironment.usage.credits(
                apiKey: apiKey,
                captureRawResponse: preferences.captureRawHTTPResponses
            )
            remainingCredits = max(credits.totalCredits - credits.totalUsage, .zero)
        } catch {
            logStore.warning("Credits summary unavailable")
        }

        let query = AnalyticsQuery.sessionCount(
            range: preferences.timeRange,
            now: now(),
            timeZone: preferences.displayTimeZone,
            customStart: preferences.customStart,
            customEnd: preferences.customEnd
        )
        do {
            let result = try await activeEnvironment.usage.queryAnalytics(
                query,
                apiKey: apiKey,
                captureRawResponse: preferences.captureRawHTTPResponses
            )
            sessionCount = result.sessionCount
            logStore.info("Received session summary for \(result.sessionCount) sessions")
        } catch {
            logStore.warning("Session summary unavailable")
        }
    }

    public func exportLogs() throws -> URL {
        let text = AppLogStore.redactForExport(logStore.text())
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = support.appendingPathComponent("MacOSAICostMonitor/exports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("console-\(Int(now().timeIntervalSince1970)).log")
        try text.write(to: url, atomically: true, encoding: .utf8)
        lastLogExportURL = url
        logStore.info("Exported sanitized console log")
        return url
    }

    private func evaluateBudget(for cost: DailyCost) {
        guard preferences.budgetEnabled else {
            budgetExceeded = false
            return
        }
        let displayed = cost.usage
        let exceeded = displayed >= Decimal(preferences.budgetAmount)
        if exceeded && !budgetExceeded && preferences.notifyOnBudget {
            logStore.warning("Budget threshold reached: \(displayed) >= \(preferences.budgetAmount)")
            BudgetNotifier.notify(
                amount: displayed,
                limit: Decimal(preferences.budgetAmount),
                decimalPlaces: preferences.decimalPlaces
            )
        }
        budgetExceeded = exceeded
    }
}

public struct FixedUTCDateProvider: UTCDateProviding {
    public let date: String
    public init(date: String) { self.date = date }
    public func currentDateString() -> String { date }
}

public extension CostMonitorModel {
    nonisolated static func utcDate(from string: String) -> Date? {
        UTCCalendar.date(from: string)
    }

    nonisolated static func utcDayOffset(from date: Date) -> Int {
        UTCCalendar.dayOffset(from: date)
    }
}
