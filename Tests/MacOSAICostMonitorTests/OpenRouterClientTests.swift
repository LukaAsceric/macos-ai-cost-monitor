import Foundation
import XCTest
@testable import MacOSAICostMonitor

final class OpenRouterClientTests: XCTestCase {
    override func tearDown() {
        TestURLProtocol.reset()
        super.tearDown()
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

    func test_decodesActivityRows() async throws {
        let body = """
        {"data":[{"date":"2026-08-17","model":"openai/gpt-5","provider_name":"OpenAI","usage":0.015,"requests":1,"prompt_tokens":10,"completion_tokens":20}]}
        """
        TestURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(body.utf8))
        }

        let client = OpenRouterClient(session: makeTestSession())
        let rows = try await client.activity(for: "2026-08-17", apiKey: "test-key")

        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].model, "openai/gpt-5")
        XCTAssertEqual(rows[0].usage, Decimal(string: "0.015"))
    }

    func test_mapsUnauthorizedResponse() async {
        TestURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 401, httpVersion: nil, headerFields: nil)!, Data())
        }
        let client = OpenRouterClient(session: makeTestSession())

        do {
            _ = try await client.activity(for: "2026-08-17", apiKey: "test-key")
            XCTFail("Expected unauthorized error")
        } catch let error as OpenRouterClientError {
            XCTAssertEqual(error, .unauthorized)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_mapsForbiddenResponseToPermissionError() async {
        TestURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 403, httpVersion: nil, headerFields: nil)!, Data())
        }
        let client = OpenRouterClient(session: makeTestSession())

        do {
            _ = try await client.activity(for: "2026-08-17", apiKey: "test-key")
            XCTFail("Expected forbidden error")
        } catch let error as OpenRouterClientError {
            XCTAssertEqual(error, .forbidden)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_mapsRateLimitAndServerErrors() async {
        for statusCode in [429, 503] {
            TestURLProtocol.requestHandler = { request in
                (HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: statusCode, httpVersion: nil, headerFields: nil)!, Data())
            }
            let client = OpenRouterClient(session: makeTestSession())

            do {
                _ = try await client.activity(for: "2026-08-17", apiKey: "test-key")
                XCTFail("Expected HTTP error")
            } catch let error as OpenRouterClientError {
                if statusCode == 429 {
                    XCTAssertEqual(error, .rateLimited)
                } else {
                    XCTAssertEqual(error, .server(statusCode: statusCode))
                }
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func test_mapsTransportFailure() async {
        TestURLProtocol.requestHandler = { _ in throw URLError(.notConnectedToInternet) }
        let client = OpenRouterClient(session: makeTestSession())

        do {
            _ = try await client.activity(for: "2026-08-17", apiKey: "test-key")
            XCTFail("Expected network error")
        } catch let error as OpenRouterClientError {
            XCTAssertEqual(error, .network)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_rejectsMalformedActivityResponse() async {
        TestURLProtocol.requestHandler = { request in
            (HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("not-json".utf8))
        }
        let client = OpenRouterClient(session: makeTestSession())

        do {
            _ = try await client.activity(for: "2026-08-17", apiKey: "test-key")
            XCTFail("Expected decoding error")
        } catch let error as OpenRouterClientError {
            XCTAssertEqual(error, .decoding)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
