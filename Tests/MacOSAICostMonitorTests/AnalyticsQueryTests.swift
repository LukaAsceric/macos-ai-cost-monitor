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
}
