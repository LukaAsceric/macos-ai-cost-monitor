import Foundation
import XCTest
@testable import MacOSAICostMonitor

final class AnalyticsQueryTests: XCTestCase {
    func test_todayUsesLocalCalendarWindowAndHourGranularity() {
        let now = UTCCalendar.parseISO8601("2026-08-17T20:59:02.061Z")!
        let timeZone = TimeZone(secondsFromGMT: 2 * 3600)!
        let query = AnalyticsQuery.make(range: .today, now: now, timeZone: timeZone, customStart: nil, customEnd: nil)

        XCTAssertEqual(query.granularity, .hour)
        XCTAssertEqual(query.timeRange.start, "2026-08-16T22:00:00.000Z")
        XCTAssertEqual(query.timeRange.end, "2026-08-17T20:59:02.061Z")
        XCTAssertTrue(query.metrics.contains("total_usage"))
        XCTAssertTrue(query.dimensions.contains("model"))
    }

    func test_past15MinutesUsesMinuteGranularity() {
        let now = UTCCalendar.parseISO8601("2026-08-17T20:59:02.061Z")!
        let query = AnalyticsQuery.make(range: .past15Minutes, now: now, timeZone: TimeZone(secondsFromGMT: 0)!, customStart: nil, customEnd: nil)
        XCTAssertEqual(query.granularity, .minute)
        XCTAssertEqual(query.timeRange.end, "2026-08-17T20:59:02.061Z")
        XCTAssertEqual(query.timeRange.start, "2026-08-17T20:44:02.061Z")
    }

    func test_decodesAnalyticsRowsWithStringCounts() throws {
        let json = """
        {"data":{"data":[{"date__hour":"2026-08-17T19:00:00.000Z","model":"openai/gpt-5","provider":"OpenAI","total_usage":0.42,"byok_usage":0.01,"request_count":"3","tokens_prompt":"10","tokens_completion":"20"}],"metadata":{"query_time_ms":12,"row_count":1,"truncated":false}}}
        """
        let decoded = try AnalyticsResponseDecoder.decode(Data(json.utf8))
        XCTAssertEqual(decoded.rows.count, 1)
        XCTAssertEqual(decoded.rows[0].usage, Decimal(string: "0.42"))
        XCTAssertEqual(decoded.rows[0].requests, 3)
        XCTAssertEqual(decoded.rows[0].model, "openai/gpt-5")
        XCTAssertFalse(decoded.truncated)
    }

    func test_sessionCountQueryGroupsBySessionWithoutTimeBuckets() {
        let now = UTCCalendar.parseISO8601("2026-08-17T20:59:02.061Z")!
        let query = AnalyticsQuery.sessionCount(
            range: .past24Hours,
            now: now,
            timeZone: TimeZone(secondsFromGMT: 0)!,
            customStart: nil,
            customEnd: nil
        )

        XCTAssertNil(query.granularity)
        XCTAssertEqual(query.metrics, ["request_count"])
        XCTAssertEqual(query.dimensions, ["session_id"])
        XCTAssertNil(query.jsonObject()["granularity"] as? String)
    }

    func test_countsDistinctNonSessionlessAnalyticsSessions() throws {
        let json = """
        {"data":{"data":[
            {"session_id":"session-a","request_count":"3"},
            {"session_id":"session-a","request_count":"2"},
            {"session_id":"session-b","request_count":"1"},
            {"session_id":"none","request_count":"4"}
        ],"metadata":{"query_time_ms":12,"row_count":4,"truncated":false}}}
        """

        let decoded = try AnalyticsResponseDecoder.decode(Data(json.utf8))

        XCTAssertEqual(decoded.sessionCount, 2)
    }
}

final class OpenRouterCreditsTests: XCTestCase {
    func test_decodesCreditsEnvelopeAndCalculatesRemainingBalance() throws {
        let json = """
        {"data":{"total_credits":100.5,"total_usage":25.75}}
        """
        let credits = try JSONDecoder().decode(CreditsEnvelopeForTesting.self, from: Data(json.utf8))
        let remaining = credits.data.totalCredits - credits.data.totalUsage

        XCTAssertEqual(remaining, Decimal(string: "74.75"))
    }
}

private struct CreditsEnvelopeForTesting: Decodable {
    let data: CreditsDataForTesting
}

private struct CreditsDataForTesting: Decodable {
    let totalCredits: Decimal
    let totalUsage: Decimal

    private enum CodingKeys: String, CodingKey {
        case totalCredits = "total_credits"
        case totalUsage = "total_usage"
    }
}
