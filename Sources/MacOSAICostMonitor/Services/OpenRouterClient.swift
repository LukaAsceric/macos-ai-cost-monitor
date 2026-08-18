import Foundation

public enum OpenRouterClientError: Error, Equatable, Sendable {
    case unauthorized
    case forbidden
    case rateLimited
    case server(statusCode: Int)
    case invalidRequest(message: String?)
    case invalidResponse
    case decoding
    case network

    public var userMessage: String {
        switch self {
        case .unauthorized:
            return "The OpenRouter key was rejected. Check that it is still active."
        case .forbidden:
            return "This endpoint requires a management key with activity access."
        case .rateLimited:
            return "OpenRouter rate-limited the refresh. Retrying later."
        case .server:
            return "OpenRouter is temporarily unavailable. Showing the last known value."
        case .invalidRequest(_):
            return "OpenRouter rejected the request. Check the requested date and management-key permissions."
        case .invalidResponse, .decoding:
            return "OpenRouter returned an unexpected response."
        case .network:
            return "OpenRouter could not be reached. Showing the last known value."
        }
    }
}

public struct OpenRouterCredits: Equatable, Sendable {
    public let totalCredits: Decimal
    public let totalUsage: Decimal

    public init(totalCredits: Decimal, totalUsage: Decimal) {
        self.totalCredits = totalCredits
        self.totalUsage = totalUsage
    }
}

public final class OpenRouterClient: UsageProvider, @unchecked Sendable {
    private struct ActivityEnvelope: Decodable {
        let data: [ActivityItem]
    }

    private struct CreditsEnvelope: Decodable {
        let data: CreditsData
    }

    private struct CreditsData: Decodable {
        let totalCredits: Decimal
        let totalUsage: Decimal

        private enum CodingKeys: String, CodingKey {
            case totalCredits = "total_credits"
            case totalUsage = "total_usage"
        }
    }

    private let baseURL: URL
    private let session: URLSession
    private let diagnosticLogStore: AppLogStore?

    public init(
        baseURL: URL = URL(string: "https://openrouter.ai/api/v1")!,
        session: URLSession = .shared,
        diagnosticLogStore: AppLogStore? = nil
    ) {
        self.baseURL = baseURL
        self.session = session
        self.diagnosticLogStore = diagnosticLogStore
    }

    public func activity(for date: String, apiKey: String) async throws -> [ActivityItem] {
        try await activity(for: date, apiKey: apiKey, captureRawResponse: false)
    }

    internal func activity(for date: String, apiKey: String, captureRawResponse: Bool) async throws -> [ActivityItem] {
        guard var components = URLComponents(url: baseURL.appendingPathComponent("activity"), resolvingAgainstBaseURL: false) else {
            throw OpenRouterClientError.invalidResponse
        }
        if !date.isEmpty {
            components.queryItems = [URLQueryItem(name: "date", value: date)]
        }
        guard let url = components.url else {
            throw OpenRouterClientError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw OpenRouterClientError.invalidResponse
            }
            if captureRawResponse {
                await logRawResponse(method: "GET", path: "/api/v1/activity", data: data, statusCode: httpResponse.statusCode)
            }
            switch httpResponse.statusCode {
            case 200..<300:
                break
            case 401:
                throw OpenRouterClientError.unauthorized
            case 403:
                throw OpenRouterClientError.forbidden
            case 429:
                throw OpenRouterClientError.rateLimited
            case 400:
                throw OpenRouterClientError.invalidRequest(message: nil)
            case 500...599:
                throw OpenRouterClientError.server(statusCode: httpResponse.statusCode)
            default:
                throw OpenRouterClientError.invalidResponse
            }

            do {
                return try JSONDecoder().decode(ActivityEnvelope.self, from: data).data
            } catch {
                throw OpenRouterClientError.decoding
            }
        } catch let error as OpenRouterClientError {
            throw error
        } catch let error as CancellationError {
            throw error
        } catch {
            if Task.isCancelled {
                throw CancellationError()
            }
            throw OpenRouterClientError.network
        }
    }

    public func recentActivity(apiKey: String) async throws -> [ActivityItem] {
        try await activity(for: "", apiKey: apiKey, captureRawResponse: false)
    }

    public func recentActivity(apiKey: String, captureRawResponse: Bool) async throws -> [ActivityItem] {
        try await activity(for: "", apiKey: apiKey, captureRawResponse: captureRawResponse)
    }

    public func credits(apiKey: String, captureRawResponse: Bool) async throws -> OpenRouterCredits {
        let url = baseURL.appendingPathComponent("credits")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw OpenRouterClientError.invalidResponse
            }
            if captureRawResponse {
                await logRawResponse(method: "GET", path: "/api/v1/credits", data: data, statusCode: httpResponse.statusCode)
            }
            switch httpResponse.statusCode {
            case 200..<300:
                break
            case 401:
                throw OpenRouterClientError.unauthorized
            case 403:
                throw OpenRouterClientError.forbidden
            case 429:
                throw OpenRouterClientError.rateLimited
            case 500...599:
                throw OpenRouterClientError.server(statusCode: httpResponse.statusCode)
            default:
                throw OpenRouterClientError.invalidResponse
            }

            do {
                let decoded = try JSONDecoder().decode(CreditsEnvelope.self, from: data)
                return OpenRouterCredits(totalCredits: decoded.data.totalCredits, totalUsage: decoded.data.totalUsage)
            } catch {
                throw OpenRouterClientError.decoding
            }
        } catch let error as OpenRouterClientError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw OpenRouterClientError.network
        }
    }

    public func queryAnalytics(_ query: AnalyticsQuery, apiKey: String, captureRawResponse: Bool) async throws -> AnalyticsQueryResult {
        let url = baseURL.appendingPathComponent("analytics").appendingPathComponent("query")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: query.jsonObject(), options: [])

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw OpenRouterClientError.invalidResponse
            }
            if captureRawResponse {
                await logRawResponse(path: "/api/v1/analytics/query", data: data, statusCode: httpResponse.statusCode)
            }
            switch httpResponse.statusCode {
            case 200..<300:
                break
            case 401:
                throw OpenRouterClientError.unauthorized
            case 403:
                throw OpenRouterClientError.forbidden
            case 429:
                throw OpenRouterClientError.rateLimited
            case 400, 408:
                throw OpenRouterClientError.invalidRequest(message: nil)
            case 500...599:
                throw OpenRouterClientError.server(statusCode: httpResponse.statusCode)
            default:
                throw OpenRouterClientError.invalidResponse
            }
            do {
                return try AnalyticsResponseDecoder.decode(data)
            } catch {
                throw OpenRouterClientError.decoding
            }
        } catch let error as OpenRouterClientError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw OpenRouterClientError.network
        }
    }

    private func logRawResponse(method: String = "POST", path: String = "/api/v1/activity", data: Data, statusCode: Int) async {
        let maxBytes = 64 * 1024
        let captured = data.prefix(maxBytes)
        let body = String(data: captured, encoding: .utf8) ?? "<non-UTF8 response>"
        let suffix = data.count > maxBytes ? "\n[truncated after \(maxBytes) bytes]" : ""
        await diagnosticLogStore?.info("HTTP response \(method) \(path) status=\(statusCode) bytes=\(data.count)")
        await diagnosticLogStore?.debug("RAW HTTP RESPONSE BODY:\n\(body)\(suffix)")
    }

    private static func extractErrorMessage(from data: Data) -> String? {
        nil
    }
}
