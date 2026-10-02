import Foundation
import XCTest
@testable import MacOSAICostMonitor

@MainActor
final class PrimaLabsClientTests: XCTestCase {
    override func tearDown() {
        TestURLProtocol.reset()
        super.tearDown()
    }

    func test_usageRequestUsesDashboardEndpointAndMapsDailyRows() async throws {
        TestURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.path, "/api/v1/litellm/usage")
            let items = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
            let query = Dictionary(uniqueKeysWithValues: items.compactMap { item in item.value.map { (item.name, $0) } })
            XCTAssertEqual(query["start"], "2026-10-01T22:00:00.000Z")
            XCTAssertEqual(query["end"], "2026-10-02T22:00:00.000Z")
            XCTAssertEqual(query["tz"], "Europe/Berlin")
            XCTAssertEqual(query["grain"], "day")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            let response = """
            {"grain":"day","spend":1.5,"daily":[
              {"date":"2026-10-01","spend":0.5,"api_requests":2,"failed_requests":0,"prompt_tokens":100,"completion_tokens":200,"cache_read_input_tokens":10,"total_tokens":300},
              {"date":"2026-10-02","spend":1.0,"api_requests":"3","failed_requests":"1","prompt_tokens":"400","completion_tokens":"500","cache_read_input_tokens":"20","total_tokens":"900"}
            ],"by_model":[{"model":"primalabs-ai/MiMo-V2.6-Pro"}]}
            """
            return (
                HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(response.utf8)
            )
        }

        let query = makeQuery(granularity: .day, timeZoneIdentifier: "Europe/Berlin")
        let client = PrimaLabsClient(session: makeTestSession())
        let result = try await client.queryAnalytics(query, apiKey: "test-token", captureRawResponse: false)

        XCTAssertEqual(result.rows.count, 2)
        XCTAssertEqual(result.rows[0].usage, Decimal(string: "0.5"))
        XCTAssertEqual(result.rows[0].requests, 2)
        XCTAssertEqual(result.rows[0].promptTokens, 100)
        XCTAssertEqual(result.rows[0].completionTokens, 200)
        XCTAssertEqual(result.rows[1].usage, Decimal(string: "1"))
        XCTAssertEqual(result.rows[1].requests, 3)
        XCTAssertEqual(result.rows[1].promptTokens, 400)
        XCTAssertEqual(result.rows[1].completionTokens, 500)
        XCTAssertEqual(result.series.count, 2)
        XCTAssertEqual(result.series.map({ $0.usage }), [Decimal(string: "0.5"), Decimal(string: "1")])
    }

    func test_hourBucketsAreParsedInTheDisplayTimeZone() async throws {
        TestURLProtocol.requestHandler = { request in
            let items = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
            let query = Dictionary(uniqueKeysWithValues: items.compactMap { item in item.value.map { (item.name, $0) } })
            XCTAssertEqual(query["grain"], "hour")
            let response = """
            {"grain":"hour","spend":0.25,"daily":[
              {"date":"2026-10-02T14:00","spend":0.25,"api_requests":1,"prompt_tokens":10,"completion_tokens":20}
            ]}
            """
            return (
                HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(response.utf8)
            )
        }

        let query = makeQuery(granularity: .hour, timeZoneIdentifier: "Europe/Berlin")
        let client = PrimaLabsClient(session: makeTestSession())
        let result = try await client.queryAnalytics(query, apiKey: "test-token", captureRawResponse: false)

        XCTAssertEqual(result.rows.count, 1)
        // 14:00 in Europe/Berlin (CEST, UTC+2) on 2026-10-02 is 12:00Z.
        XCTAssertEqual(
            result.rows[0].timestamp.map(UTCCalendar.iso8601String(from:)),
            "2026-10-02T12:00:00.000Z"
        )
    }

    func test_minuteGranularityRequestsHourGrain() async throws {
        TestURLProtocol.requestHandler = { request in
            let items = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
            let query = Dictionary(uniqueKeysWithValues: items.compactMap { item in item.value.map { (item.name, $0) } })
            XCTAssertEqual(query["grain"], "hour")
            return (
                HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(#"{"grain":"hour","daily":[]}"#.utf8)
            )
        }

        let query = makeQuery(granularity: .minute, timeZoneIdentifier: "Europe/Berlin")
        let client = PrimaLabsClient(session: makeTestSession())
        _ = try await client.queryAnalytics(query, apiKey: "test-token", captureRawResponse: false)
    }

    func test_walletCentsMapToCreditsRemainingBalance() async throws {
        TestURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/v1/billing/wallet")
            let response = """
            {"balance_cents":12345,"lifetime_topup_cents":20000,"granted_credit_cents":0,"promo_credit_cents":0,"spent_cents":7655}
            """
            return (
                HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(response.utf8)
            )
        }

        let client = PrimaLabsClient(session: makeTestSession())
        let credits = try await client.credits(apiKey: "test-token", captureRawResponse: false)

        // remaining = max(totalCredits - totalUsage, 0) must equal the available balance in dollars.
        XCTAssertEqual(credits.totalCredits - credits.totalUsage, Decimal(string: "123.45"))
    }

    func test_sessionCountQueryReturnsNoRowsWithoutNetworkTraffic() async throws {
        TestURLProtocol.requestHandler = { _ in
            XCTFail("Session queries must not reach the network")
            throw TestStorageError.unavailable
        }

        let query = AnalyticsQuery.sessionCount(
            range: .today,
            now: Date(timeIntervalSince1970: 1_790_000_000),
            timeZone: TimeZone(secondsFromGMT: 0)!,
            customStart: nil,
            customEnd: nil
        )
        let client = PrimaLabsClient(session: makeTestSession())
        let result = try await client.queryAnalytics(query, apiKey: "test-token", captureRawResponse: false)

        XCTAssertEqual(result.rows.count, 0)
        XCTAssertEqual(result.sessionCount, 0)
    }

    func test_expiredTokenProducesExpiryGuidance() async throws {
        TestURLProtocol.requestHandler = { request in
            (
                HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 401, httpVersion: nil, headerFields: nil)!,
                Data(#"{"detail":"unauthorized"}"#.utf8)
            )
        }

        let client = PrimaLabsClient(session: makeTestSession())
        do {
            _ = try await client.queryAnalytics(
                makeQuery(granularity: .day, timeZoneIdentifier: "Europe/Berlin"),
                apiKey: "test-token",
                captureRawResponse: false
            )
            XCTFail("Expected unauthorized error")
        } catch let error as PrimaLabsClientError {
            XCTAssertEqual(error, .unauthorized)
            XCTAssertTrue(error.userMessage.contains("expired"))
            XCTAssertTrue(error.userMessage.contains("dashboard"))
        }
    }

    func test_rawResponseCaptureNeverLogsTheToken() async throws {
        let logs = AppLogStore()
        TestURLProtocol.requestHandler = { request in
            (
                HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(#"{"grain":"day","daily":[]}"#.utf8)
            )
        }

        let client = PrimaLabsClient(session: makeTestSession(), diagnosticLogStore: logs)
        _ = try await client.queryAnalytics(
            makeQuery(granularity: .day, timeZoneIdentifier: "Europe/Berlin"),
                apiKey: "super-secret-token",
            captureRawResponse: true
        )

        let text = logs.text()
        XCTAssertTrue(text.contains("RAW HTTP RESPONSE BODY"))
        XCTAssertFalse(text.contains("super-secret-token"))
    }

    private func makeQuery(granularity: AnalyticsGranularity, timeZoneIdentifier: String) -> AnalyticsQuery {
        AnalyticsQuery(
            metrics: AnalyticsQuery.defaultMetrics,
            dimensions: ["model"],
            granularity: granularity,
            timeRange: AnalyticsTimeRange(
                start: "2026-10-01T22:00:00.000Z",
                end: "2026-10-02T22:00:00.000Z"
            ),
            orderByField: "date",
            orderDirection: "asc",
            limit: 10,
            includeEnrichment: true,
            timeZoneIdentifier: timeZoneIdentifier
        )
    }
}
