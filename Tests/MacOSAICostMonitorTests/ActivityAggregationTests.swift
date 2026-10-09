import Foundation
import XCTest
@testable import MacOSAICostMonitor

final class ActivityAggregationTests: XCTestCase {
    func test_aggregatesUsageTokensAndRequestsAcrossRows() throws {
        let items = try fixtureItems()
        let result = ActivityAggregator.aggregate(items, for: "2026-08-17")

        XCTAssertEqual(result.usage, Decimal(string: "0.0192"))
        XCTAssertEqual(result.requests, 7)
        XCTAssertEqual(result.promptTokens, 70)
        XCTAssertEqual(result.completionTokens, 165)
        XCTAssertEqual(result.reasoningTokens, 25)
        XCTAssertEqual(result.breakdowns.count, 2)
    }

    func test_keepsByokEstimateSeparateFromOpenRouterUsage() throws {
        let result = ActivityAggregator.aggregate(try fixtureItems(), for: "2026-08-17")

        XCTAssertEqual(result.usage, Decimal(string: "0.0192"))
        XCTAssertEqual(result.byokUsageInference, Decimal(string: "0.002"))
    }

    func test_ignoresRowsForADifferentDateWhenAggregatingDefensively() {
        let items = [
            ActivityItem(
                date: "2026-08-16",
                model: "openai/gpt-5",
                providerName: "OpenAI",
                usage: Decimal(string: "99")!,
                requests: 99,
                promptTokens: 99,
                completionTokens: 99,
                reasoningTokens: 99
            )
        ]

        let result = ActivityAggregator.aggregate(items, for: "2026-08-17")

        XCTAssertEqual(result, .empty(for: "2026-08-17"))
    }

    func test_emptyActivityProducesZeroSummaryForRequestedDate() {
        XCTAssertEqual(ActivityAggregator.aggregate([], for: "2026-08-17"), .empty(for: "2026-08-17"))
    }

    func test_missingOptionalReasoningTokensIsTreatedAsZero() throws {
        let result = ActivityAggregator.aggregate(try fixtureItems(), for: "2026-08-17")

        XCTAssertEqual(result.reasoningTokens, 25)
        XCTAssertEqual(result.breakdowns.first(where: { $0.provider == "Anthropic" })?.reasoningTokens, 0)
    }

    // MARK: - Grouping across providers

    func test_groupedByModelMergesSameModelAcrossProviders() {
        let rows = [
            CostBreakdown(model: "openai/gpt-5", provider: "OpenAI", usage: Decimal(string: "0.015")!,
                          requests: 5, promptTokens: 50, completionTokens: 125, reasoningTokens: 25),
            CostBreakdown(model: "openai/gpt-5", provider: "Together", usage: Decimal(string: "0.003")!,
                          requests: 2, promptTokens: 20, completionTokens: 40, reasoningTokens: 0),
            CostBreakdown(model: "anthropic/claude-sonnet", provider: "Anthropic", usage: Decimal(string: "0.0042")!,
                          requests: 2, promptTokens: 20, completionTokens: 40, reasoningTokens: 0)
        ]

        let grouped = rows.groupedByModel()

        XCTAssertEqual(grouped.count, 2)
        let gpt = try? XCTUnwrap(grouped.first(where: { $0.model == "openai/gpt-5" }))
        XCTAssertEqual(gpt?.usage, Decimal(string: "0.018"))
        XCTAssertEqual(gpt?.requests, 7)
        XCTAssertEqual(gpt?.promptTokens, 70)
        XCTAssertEqual(gpt?.completionTokens, 165)
        XCTAssertEqual(gpt?.reasoningTokens, 25)
        XCTAssertTrue(gpt?.provider.contains("OpenAI") == true)
        XCTAssertTrue(gpt?.provider.contains("Together") == true)
    }

    func test_groupedByModelKeepsSingleProviderRowsUnchanged() {
        let rows = [
            CostBreakdown(model: "openai/gpt-5", provider: "OpenAI", usage: Decimal(string: "0.015")!,
                          requests: 5, promptTokens: 50, completionTokens: 125, reasoningTokens: 25)
        ]

        let grouped = rows.groupedByModel()

        XCTAssertEqual(grouped.count, 1)
        XCTAssertEqual(grouped.first?.provider, "OpenAI")
        XCTAssertEqual(grouped.first?.usage, Decimal(string: "0.015"))
    }

    func test_groupedByModelEmptyInputIsEmpty() {
        XCTAssertTrue([CostBreakdown]().groupedByModel().isEmpty)
    }

    func test_groupedByProviderMergesSameProviderAcrossModels() {
        let rows = [
            CostBreakdown(model: "openai/gpt-5", provider: "OpenRouter", usage: Decimal(string: "0.015")!,
                          requests: 5, promptTokens: 50, completionTokens: 125, reasoningTokens: 25),
            CostBreakdown(model: "anthropic/claude-sonnet", provider: "OpenRouter", usage: Decimal(string: "0.003")!,
                          requests: 2, promptTokens: 20, completionTokens: 40, reasoningTokens: 0),
            CostBreakdown(model: "xiaomi/mimo-v2.6-pro", provider: "PrimaLabs", usage: Decimal(string: "0.0042")!,
                          requests: 2, promptTokens: 20, completionTokens: 40, reasoningTokens: 0)
        ]

        let grouped = rows.groupedByProvider()

        XCTAssertEqual(grouped.count, 2)
        let openRouter = try? XCTUnwrap(grouped.first(where: { $0.provider == "OpenRouter" }))
        XCTAssertEqual(openRouter?.usage, Decimal(string: "0.018"))
        XCTAssertEqual(openRouter?.requests, 7)
        XCTAssertEqual(openRouter?.promptTokens, 70)
        XCTAssertEqual(openRouter?.completionTokens, 165)
        XCTAssertEqual(openRouter?.reasoningTokens, 25)
        XCTAssertTrue(openRouter?.model.contains("openai/gpt-5") == true)
        XCTAssertTrue(openRouter?.model.contains("anthropic/claude-sonnet") == true)
    }

    func test_groupedByProviderSortsByDescendingUsage() {
        let rows = [
            CostBreakdown(model: "model-a", provider: "Small", usage: Decimal(string: "0.001")!,
                          requests: 1, promptTokens: 1, completionTokens: 1, reasoningTokens: 0),
            CostBreakdown(model: "model-b", provider: "Large", usage: Decimal(string: "0.009")!,
                          requests: 1, promptTokens: 1, completionTokens: 1, reasoningTokens: 0)
        ]

        XCTAssertEqual(rows.groupedByProvider().map(\.provider), ["Large", "Small"])
    }

    func test_groupedByProviderKeepsSingleModelRowsUnchanged() {
        let rows = [
            CostBreakdown(model: "openai/gpt-5", provider: "OpenRouter", usage: Decimal(string: "0.015")!,
                          requests: 5, promptTokens: 50, completionTokens: 125, reasoningTokens: 25)
        ]

        let grouped = rows.groupedByProvider()

        XCTAssertEqual(grouped.count, 1)
        XCTAssertEqual(grouped.first?.provider, "OpenRouter")
        XCTAssertEqual(grouped.first?.model, "openai/gpt-5")
        XCTAssertEqual(grouped.first?.usage, Decimal(string: "0.015"))
    }

    func test_groupedByProviderEmptyInputIsEmpty() {
        XCTAssertTrue([CostBreakdown]().groupedByProvider().isEmpty)
    }

    private func fixtureItems() throws -> [ActivityItem] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "activity-response", withExtension: "json"))
        let data = try Data(contentsOf: url)
        struct Envelope: Decodable { let data: [ActivityItem] }
        return try JSONDecoder().decode(Envelope.self, from: data).data
    }
}
