import Foundation
import XCTest
@testable import MacOSAICostMonitor

@MainActor
final class OpenRouterClientTests: XCTestCase {
    override func tearDown() {
        TestURLProtocol.reset()
        super.tearDown()
    }

    func test_queryAnalyticsPostsBrowserCompatiblePayload() async throws {
        TestURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/api/v1/analytics/query")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-management-key")
            let body = try JSONSerialization.jsonObject(with: requestBodyData(request)) as? [String: Any]
            XCTAssertEqual(body?["granularity"] as? String, "hour")
            XCTAssertEqual((body?["metrics"] as? [String])?.contains("total_usage"), true)
            let range = body?["time_range"] as? [String: String]
            XCTAssertEqual(range?["start"], "2026-08-16T22:00:00.000Z")
            let response = """
            {"data":{"data":[{"date__hour":"2026-08-17T19:00:00.000Z","model":"openai/gpt-5","total_usage":0.015,"request_count":"1","tokens_prompt":"10","tokens_completion":"20"}],"metadata":{"query_time_ms":1,"row_count":1,"truncated":false}}}
            """
            return (HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(response.utf8))
        }

        let now = UTCCalendar.parseISO8601("2026-08-17T20:59:02.061Z")!
        let query = AnalyticsQuery.make(
            range: .today,
            now: now,
            timeZone: TimeZone(secondsFromGMT: 2 * 3600)!,
            customStart: nil,
            customEnd: nil
        )
        let client = OpenRouterClient(session: makeTestSession())
        let result = try await client.queryAnalytics(query, apiKey: "test-management-key", captureRawResponse: false)
        XCTAssertEqual(result.rows.count, 1)
        XCTAssertEqual(result.rows[0].usage, Decimal(string: "0.015"))
    }

    func test_requestsActivityForUtcDateWithBearerManagementKey() async throws {
        let responseData = Data("{\"data\":[]}".utf8)
        TestURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/v1/activity")
            XCTAssertEqual(request.url?.query, "date=2026-08-17")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-management-key")
            return (HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!, responseData)
        }

        let client = OpenRouterClient(session: makeTestSession())
        let result = try await client.activity(for: "2026-08-17", apiKey: "test-management-key")
        XCTAssertTrue(result.isEmpty)
    }

    func test_rawResponseCaptureLogsBodyWithoutAuthorizationHeader() async throws {
        let logs = AppLogStore()
        let body = "{\"data\":[],\"diagnostic\":\"visible\"}"
        TestURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            return (HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }

        let client = OpenRouterClient(session: makeTestSession(), diagnosticLogStore: logs)
        _ = try await client.activity(for: "", apiKey: "test-key", captureRawResponse: true)
        let text = logs.text()
        XCTAssertTrue(text.contains("RAW HTTP RESPONSE BODY"))
        XCTAssertTrue(text.contains("visible"))
        XCTAssertFalse(text.contains("test-key"))
    }
}
