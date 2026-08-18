import Foundation
import XCTest
@testable import MacOSAICostMonitor

final class CostMonitorModelTests: XCTestCase {
    @MainActor
    func test_managementKeyStatusReflectsMissingKeyWithoutExposingValue() async {
        let model = CostMonitorModel(
            provider: FakeUsageProvider(items: []),
            secretStore: InMemorySecretStore(),
            cache: InMemoryCostCache(),
            dateProvider: FixedUTCDateProvider(date: "2026-08-17")
        )

        XCTAssertEqual(model.managementKeyStatus, .unknown)
        await model.refresh()

        XCTAssertEqual(model.managementKeyStatus, .missing)
        XCTAssertFalse(String(describing: model.managementKeyStatus).contains("test-key"))
    }

    @MainActor
    func test_refreshLogsSanitizedDiagnosticSummary() async {
        let logs = AppLogStore()
        let model = CostMonitorModel(
            provider: FakeUsageProvider(items: []),
            secretStore: InMemorySecretStore(value: "test-key"),
            cache: InMemoryCostCache(),
            dateProvider: FixedUTCDateProvider(date: "2026-08-17"),
            logStore: logs
        )

        await model.refresh()

        XCTAssertTrue(logs.entries.contains { $0.message == "Querying OpenRouter analytics" })
        XCTAssertTrue(logs.entries.contains { $0.message.contains("Received 0 analytics rows") })
        XCTAssertFalse(logs.text().contains("test-key"))
    }

    func test_refreshReadsSecretFromKeychainOnlyOncePerModelLifetime() async {
        let secretStore = CountingSecretStore(value: "test-key")
        let item = ActivityItem(
            date: "2026-08-17",
            model: "openai/gpt-5",
            providerName: "OpenAI",
            usage: Decimal(string: "0.015")!,
            requests: 1,
            promptTokens: 10,
            completionTokens: 20
        )
        let model = await MainActor.run {
            CostMonitorModel(
                provider: FakeUsageProvider(items: [item]),
                secretStore: secretStore,
                cache: InMemoryCostCache(),
                dateProvider: FixedUTCDateProvider(date: "2026-08-17")
            )
        }

        await model.refresh()
        await model.refresh()

        XCTAssertEqual(secretStore.readCount(), 1)
    }

    @MainActor
    func test_reportingPreferencesPersistAndClampDecimals() {
        let suiteName = "CostMonitorModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = ReportingPreferences(defaults: defaults)
        preferences.decimalPlaces = 12
        preferences.reportRange = .last30Days

        XCTAssertEqual(preferences.decimalPlaces, 8)
        XCTAssertEqual(defaults.string(forKey: "reportRange"), ReportRange.last30Days.rawValue)
    }

    func test_systemDateProviderRequestsLatestCompletedUtcDate() {
        let provider = SystemUTCDateProvider(now: { Date(timeIntervalSince1970: 86_400) })

        XCTAssertEqual(provider.currentDateString(), "1970-01-01")
    }

    func test_missingKeyStartsInSetupState() async {
        let model = await MainActor.run {
            CostMonitorModel(
                provider: FakeUsageProvider(items: []),
                secretStore: InMemorySecretStore(),
                cache: InMemoryCostCache(),
                dateProvider: FixedUTCDateProvider(date: "2026-08-17")
            )
        }

        await model.refresh()

        let state = await MainActor.run { model.state }
        XCTAssertEqual(state, .notConfigured)
    }

    func test_successfulRefreshPublishesAggregatedCostAndAccountSummary() async {
        let item = ActivityItem(
            date: "2026-08-17",
            model: "openai/gpt-5",
            providerName: "OpenAI",
            usage: Decimal(string: "0.015")!,
            requests: 1,
            promptTokens: 10,
            completionTokens: 20,
            reasoningTokens: 2
        )
        let cache = InMemoryCostCache()
        let model = await MainActor.run {
            CostMonitorModel(
                provider: FakeUsageProvider(
                    items: [item],
                    credits: OpenRouterCredits(totalCredits: Decimal(string: "100")!, totalUsage: Decimal(string: "25")!),
                    sessionResult: AnalyticsQueryResult(rows: [
                        AnalyticsRow(timestamp: nil, model: "unknown", provider: "OpenRouter", usage: .zero, byokUsage: .zero, requests: 1, promptTokens: 0, completionTokens: 0, sessionID: "session-1"),
                        AnalyticsRow(timestamp: nil, model: "unknown", provider: "OpenRouter", usage: .zero, byokUsage: .zero, requests: 1, promptTokens: 0, completionTokens: 0, sessionID: "session-2")
                    ], truncated: false)
                ),
                secretStore: InMemorySecretStore(value: "test-key"),
                cache: cache,
                dateProvider: FixedUTCDateProvider(date: "2026-08-17"),
                now: { Date(timeIntervalSince1970: 123) }
            )
        }

        await model.refresh()

        let state = await MainActor.run { model.state }
        guard case .loaded(let cost, let fetchedAt, let stale) = state else {
            return XCTFail("Expected loaded state, got \(state)")
        }
        XCTAssertEqual(cost.usage, Decimal(string: "0.015"))
        XCTAssertEqual(fetchedAt, Date(timeIntervalSince1970: 123))
        XCTAssertFalse(stale)
        XCTAssertEqual(cache.load()?.cost, cost)
        let summary = await MainActor.run { (model.remainingCredits, model.sessionCount) }
        XCTAssertEqual(summary.0, Decimal(string: "75"))
        XCTAssertEqual(summary.1, 2)
    }

    func test_emptyRecentActivityPublishesNoData() async {
        let model = await MainActor.run {
            CostMonitorModel(
                provider: FakeUsageProvider(items: []),
                secretStore: InMemorySecretStore(value: "test-key"),
                cache: InMemoryCostCache(),
                dateProvider: FixedUTCDateProvider(date: "2026-08-17"),
                now: { Date(timeIntervalSince1970: 456) }
            )
        }

        await model.refresh()

        let state = await MainActor.run { model.state }
        XCTAssertEqual(state, .noData(date: "Latest completed UTC day", fetchedAt: Date(timeIntervalSince1970: 456), previous: nil))
    }

    func test_noDataPreservesPreviousValue() async {
        let previous = DailyCost.empty(for: "2026-08-17")
        let model = await MainActor.run {
            CostMonitorModel(
                provider: FakeUsageProvider(items: []),
                secretStore: InMemorySecretStore(value: "test-key"),
                cache: InMemoryCostCache(value: CachedUsage(cost: previous, fetchedAt: Date(timeIntervalSince1970: 10))),
                dateProvider: FixedUTCDateProvider(date: "2026-08-17"),
                now: { Date(timeIntervalSince1970: 20) }
            )
        }

        await model.refresh()

        let state = await MainActor.run { model.state }
        XCTAssertEqual(state.dailyCost, previous)
        guard case .noData(_, _, let preserved) = state else {
            return XCTFail("Expected no-data state")
        }
        XCTAssertEqual(preserved, previous)
    }

    func test_cachedPreviousDayRemainsVisibleUntilNewActivityArrives() async {
        let previous = DailyCost.empty(for: "2026-08-16")
        let model = await MainActor.run {
            CostMonitorModel(
                provider: FakeUsageProvider(items: []),
                secretStore: InMemorySecretStore(value: "test-key"),
                cache: InMemoryCostCache(value: CachedUsage(cost: previous, fetchedAt: Date(timeIntervalSince1970: 10))),
                dateProvider: FixedUTCDateProvider(date: "2026-08-17")
            )
        }

        let state = await MainActor.run { model.state }
        XCTAssertEqual(state.dailyCost, previous)
    }

    func test_cacheWriteFailureDoesNotDiscardSuccessfulLiveResult() async {
        let item = ActivityItem(
            date: "2026-08-17",
            model: "openai/gpt-5",
            providerName: "OpenAI",
            usage: Decimal(string: "0.015")!,
            requests: 1,
            promptTokens: 10,
            completionTokens: 20
        )
        let model = await MainActor.run {
            CostMonitorModel(
                provider: FakeUsageProvider(items: [item]),
                secretStore: InMemorySecretStore(value: "test-key"),
                cache: FailingCostCache(),
                dateProvider: FixedUTCDateProvider(date: "2026-08-17")
            )
        }

        await model.refresh()

        let state = await MainActor.run { model.state }
        guard case .loaded(let cost, _, let stale) = state else {
            return XCTFail("Expected live result despite cache failure")
        }
        XCTAssertEqual(cost.usage, Decimal(string: "0.015"))
        XCTAssertFalse(stale)
    }

    func test_forbiddenFailureExplainsManagementKeyRequirement() async {
        let model = await MainActor.run {
            CostMonitorModel(
                provider: FakeUsageProvider(error: OpenRouterClientError.forbidden),
                secretStore: InMemorySecretStore(value: "test-key"),
                cache: InMemoryCostCache(),
                dateProvider: FixedUTCDateProvider(date: "2026-08-17")
            )
        }

        await model.refresh()

        let state = await MainActor.run { model.state }
        guard case .failed(let message, _, _) = state else {
            return XCTFail("Expected failed state")
        }
        XCTAssertTrue(message.contains("management key"))
        XCTAssertTrue(message.contains("activity access"))
    }

    func test_overlappingRefreshesAwaitTheSameOperation() async {
        let provider = BlockingUsageProvider()
        let model = await MainActor.run {
            CostMonitorModel(
                provider: provider,
                secretStore: InMemorySecretStore(value: "test-key"),
                cache: InMemoryCostCache(),
                dateProvider: FixedUTCDateProvider(date: "2026-08-17")
            )
        }

        let first = Task { await model.refresh() }
        await provider.waitUntilCalled()
        let second = Task { await model.refresh() }
        await provider.release()

        let results = await (first.value, second.value)
        XCTAssertEqual(results.0, true)
        XCTAssertEqual(results.1, true)
        let calls = await provider.callCount()
        XCTAssertEqual(calls, 1)
    }

    func test_networkFailureKeepsLastValueButMarksItStale() async {
        let previous = DailyCost.empty(for: "2026-08-17")
        let model = await MainActor.run {
            CostMonitorModel(
                provider: FakeUsageProvider(error: OpenRouterClientError.network),
                secretStore: InMemorySecretStore(value: "test-key"),
                cache: InMemoryCostCache(value: CachedUsage(cost: previous, fetchedAt: Date(timeIntervalSince1970: 10))),
                dateProvider: FixedUTCDateProvider(date: "2026-08-17"),
                now: { Date(timeIntervalSince1970: 20) }
            )
        }

        await model.refresh()

        let state = await MainActor.run { model.state }
        guard case .failed(let message, let value, let staleSince) = state else {
            return XCTFail("Expected failed state")
        }
        XCTAssertTrue(message.contains("could not be reached"))
        XCTAssertEqual(value, previous)
        XCTAssertEqual(staleSince, Date(timeIntervalSince1970: 10))
    }

    @MainActor
    func test_exportWritesRedactedFile() async throws {
        let store = AppLogStore()
        store.info("token=secret-value")
        let model = CostMonitorModel(
            provider: FakeUsageProvider(),
            secretStore: InMemorySecretStore(),
            cache: InMemoryCostCache(),
            logStore: store
        )
        let url = try model.exportLogs()
        let text = try String(contentsOf: url)
        XCTAssertFalse(text.contains("secret-value"))
        XCTAssertTrue(text.contains("[REDACTED]"))
    }
}

private final class FakeUsageProvider: UsageProvider, @unchecked Sendable {
    let items: [ActivityItem]
    let error: Error?
    let creditsValue: OpenRouterCredits?
    let sessionResult: AnalyticsQueryResult?

    init(
        items: [ActivityItem] = [],
        error: Error? = nil,
        credits: OpenRouterCredits? = nil,
        sessionResult: AnalyticsQueryResult? = nil
    ) {
        self.items = items
        self.error = error
        self.creditsValue = credits
        self.sessionResult = sessionResult
    }

    func activity(for date: String, apiKey: String) async throws -> [ActivityItem] {
        if let error { throw error }
        return items
    }

    func recentActivity(apiKey: String) async throws -> [ActivityItem] {
        if let error { throw error }
        return items
    }

    func recentActivity(apiKey: String, captureRawResponse: Bool) async throws -> [ActivityItem] {
        try await recentActivity(apiKey: apiKey)
    }

    func queryAnalytics(_ query: AnalyticsQuery, apiKey: String, captureRawResponse: Bool) async throws -> AnalyticsQueryResult {
        if let error { throw error }
        if query.dimensions == ["session_id"] {
            return sessionResult ?? AnalyticsQueryResult(rows: [], truncated: false)
        }
        return AnalyticsQueryResult(
            rows: items.map {
                AnalyticsRow(
                    timestamp: UTCCalendar.date(from: $0.date),
                    model: $0.model,
                    provider: $0.providerName,
                    usage: $0.usage,
                    byokUsage: $0.byokUsageInference ?? .zero,
                    requests: $0.requests,
                    promptTokens: $0.promptTokens,
                    completionTokens: $0.completionTokens
                )
            },
            truncated: false
        )
    }

    func credits(apiKey: String, captureRawResponse: Bool) async throws -> OpenRouterCredits {
        if let error { throw error }
        guard let creditsValue else { throw OpenRouterClientError.invalidResponse }
        return creditsValue
    }
}
