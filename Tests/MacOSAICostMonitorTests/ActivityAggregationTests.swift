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

    private func fixtureItems() throws -> [ActivityItem] {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "activity-response", withExtension: "json"))
        let data = try Data(contentsOf: url)
        struct Envelope: Decodable { let data: [ActivityItem] }
        return try JSONDecoder().decode(Envelope.self, from: data).data
    }
}
