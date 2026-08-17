import Foundation
import XCTest
@testable import MacOSAICostMonitor

final class CostMonitorModelTests: XCTestCase {
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

    func test_successfulRefreshPublishesAggregatedCostAndCachesIt() async {
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
                provider: FakeUsageProvider(items: [item]),
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
        XCTAssertEqual(state, .noData(date: "2026-08-17", fetchedAt: Date(timeIntervalSince1970: 456), previous: nil))
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
}

private final class FakeUsageProvider: UsageProvider, @unchecked Sendable {
    let items: [ActivityItem]
    let error: Error?

    init(items: [ActivityItem] = [], error: Error? = nil) {
        self.items = items
        self.error = error
    }

    func activity(for date: String, apiKey: String) async throws -> [ActivityItem] {
        if let error { throw error }
        return items
    }

    func recentActivity(apiKey: String) async throws -> [ActivityItem] {
        if let error { throw error }
        return items
    }
}
