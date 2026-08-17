import Foundation

public enum OpenRouterClientError: Error, Equatable, Sendable {
    case unauthorized
    case forbidden
    case rateLimited
    case server(statusCode: Int)
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
        case .invalidResponse, .decoding:
            return "OpenRouter returned an unexpected response."
        case .network:
            return "OpenRouter could not be reached. Showing the last known value."
        }
    }
}

public final class OpenRouterClient: UsageProvider, @unchecked Sendable {
    private struct ActivityEnvelope: Decodable {
        let data: [ActivityItem]
    }

    private let baseURL: URL
    private let session: URLSession

    public init(
        baseURL: URL = URL(string: "https://openrouter.ai/api/v1")!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    public func activity(for date: String, apiKey: String) async throws -> [ActivityItem] {
        guard var components = URLComponents(url: baseURL.appendingPathComponent("activity"), resolvingAgainstBaseURL: false) else {
            throw OpenRouterClientError.invalidResponse
        }
        components.queryItems = [URLQueryItem(name: "date", value: date)]
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
}
