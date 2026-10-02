import Foundation

public enum PrimaLabsClientError: Error, Equatable, Sendable {
    case unauthorized
    case rateLimited
    case server(statusCode: Int)
    case invalidRequest(message: String?)
    case invalidResponse
    case decoding
    case network

    public var userMessage: String {
        switch self {
        case .unauthorized:
            return "The PrimaLabs dashboard token was rejected or has expired. Open the dashboard, copy a fresh token, and save it again."
        case .rateLimited:
            return "PrimaLabs rate-limited the refresh. Retrying later."
        case .server:
            return "PrimaLabs is temporarily unavailable. Showing the last known value."
        case .invalidRequest:
            return "PrimaLabs rejected the request. Check the requested window."
        case .invalidResponse, .decoding:
            return "PrimaLabs returned an unexpected response."
        case .network:
            return "PrimaLabs could not be reached. Showing the last known value."
        }
    }
}

/// Talks to the PrimaLabs dashboard API. PrimaLabs exposes no public
/// analytics endpoint on `api.primalabs.ai`; usage, per-request logs, and the
/// prepaid wallet live behind the dashboard session token instead.
public final class PrimaLabsClient: UsageProvider, @unchecked Sendable {
    private struct FlexInt: Decodable {
        let value: Int

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let int = try? container.decode(Int.self) {
                value = int
            } else if let string = try? container.decode(String.self), let int = Int(string) {
                value = int
            } else {
                value = 0
            }
        }
    }

    private struct FlexDecimal: Decodable {
        let value: Decimal

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let number = try? container.decode(Decimal.self) {
                value = number
            } else if let string = try? container.decode(String.self) {
                value = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")) ?? .zero
            } else {
                value = .zero
            }
        }
    }

    private struct UsageBucket: Decodable {
        let date: String
        let spend: FlexDecimal?
        let apiRequests: FlexInt?
        let promptTokens: FlexInt?
        let completionTokens: FlexInt?

        enum CodingKeys: String, CodingKey {
            case date, spend
            case apiRequests = "api_requests"
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
        }
    }

    private struct UsageResponse: Decodable {
        let grain: String?
        let spend: FlexDecimal?
        let daily: [UsageBucket]?

        enum CodingKeys: String, CodingKey {
            case grain, spend, daily
        }
    }

    private struct WalletResponse: Decodable {
        let balanceCents: FlexInt?
        let spentCents: FlexInt?

        enum CodingKeys: String, CodingKey {
            case balanceCents = "balance_cents"
            case spentCents = "spent_cents"
        }
    }

    public static let defaultBaseURL = URL(string: "https://dashboard.primalabs.ai")!
    public static let aggregateModelName = "All models"

    private let baseURL: URL
    private let session: URLSession
    private let diagnosticLogStore: AppLogStore?

    public init(
        baseURL: URL = PrimaLabsClient.defaultBaseURL,
        session: URLSession = .shared,
        diagnosticLogStore: AppLogStore? = nil
    ) {
        self.baseURL = baseURL
        self.session = session
        self.diagnosticLogStore = diagnosticLogStore
    }

    public func activity(for date: String, apiKey: String) async throws -> [ActivityItem] {
        let start = "\(date)T00:00:00.000Z"
        let end = "\(date)T23:59:59.999Z"
        let query = AnalyticsQuery(
            metrics: AnalyticsQuery.defaultMetrics,
            dimensions: ["model"],
            granularity: .day,
            timeRange: AnalyticsTimeRange(start: start, end: end),
            orderByField: "date",
            orderDirection: "asc",
            limit: 100,
            includeEnrichment: false,
            timeZoneIdentifier: "UTC"
        )
        let result = try await queryAnalytics(query, apiKey: apiKey, captureRawResponse: false)
        return result.rows.map { $0.asActivityItem() }
    }

    public func queryAnalytics(
        _ query: AnalyticsQuery,
        apiKey: String,
        captureRawResponse: Bool
    ) async throws -> AnalyticsQueryResult {
        // PrimaLabs has no session concept; the model derives "Sessions" from
        // distinct session IDs, so the session summary is answered without traffic.
        if query.dimensions == ["session_id"] {
            return AnalyticsQueryResult(rows: [], truncated: false)
        }

        let grain = (query.granularity == .hour || query.granularity == .minute) ? "hour" : "day"
        let timeZoneIdentifier = query.timeZoneIdentifier ?? "UTC"
        let response = try await usageResponse(
            start: query.timeRange.start,
            end: query.timeRange.end,
            timeZoneIdentifier: timeZoneIdentifier,
            grain: grain,
            apiKey: apiKey,
            captureRawResponse: captureRawResponse
        )
        let timeZone = TimeZone(identifier: timeZoneIdentifier) ?? TimeZone(secondsFromGMT: 0)!
        let rows: [AnalyticsRow] = (response.daily ?? []).map { bucket -> AnalyticsRow in
            AnalyticsRow(
                timestamp: Self.bucketDate(from: bucket.date, timeZone: timeZone),
                model: Self.aggregateModelName,
                provider: "PrimaLabs",
                usage: bucket.spend?.value ?? .zero,
                byokUsage: .zero,
                requests: bucket.apiRequests?.value ?? 0,
                promptTokens: bucket.promptTokens?.value ?? 0,
                completionTokens: bucket.completionTokens?.value ?? 0
            )
        }
        return AnalyticsQueryResult(rows: rows, truncated: false)
    }

    public func credits(apiKey: String, captureRawResponse: Bool) async throws -> OpenRouterCredits {
        let wallet: WalletResponse = try await get(
            path: "/api/v1/billing/wallet",
            apiKey: apiKey,
            captureRawResponse: captureRawResponse
        )
        let balance = Decimal(wallet.balanceCents?.value ?? 0) / 100
        let spent = Decimal(wallet.spentCents?.value ?? 0) / 100
        // `max(totalCredits - totalUsage, 0)` must equal the available balance.
        return OpenRouterCredits(totalCredits: balance + spent, totalUsage: spent)
    }

    private func usageResponse(
        start: String,
        end: String,
        timeZoneIdentifier: String,
        grain: String,
        apiKey: String,
        captureRawResponse: Bool
    ) async throws -> UsageResponse {
        try await get(
            path: "/api/v1/litellm/usage",
            queryItems: [
                URLQueryItem(name: "start", value: start),
                URLQueryItem(name: "end", value: end),
                URLQueryItem(name: "tz", value: timeZoneIdentifier),
                URLQueryItem(name: "grain", value: grain)
            ],
            apiKey: apiKey,
            captureRawResponse: captureRawResponse
        )
    }

    private func get<T: Decodable>(
        path: String,
        queryItems: [URLQueryItem] = [],
        apiKey: String,
        captureRawResponse: Bool
    ) async throws -> T {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw PrimaLabsClientError.invalidResponse
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw PrimaLabsClientError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let data: Data
        do {
            let (body, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw PrimaLabsClientError.invalidResponse
            }
            if captureRawResponse {
                await logRawResponse(path: path, data: body, statusCode: httpResponse.statusCode)
            }
            switch httpResponse.statusCode {
            case 200..<300:
                data = body
            case 401:
                throw PrimaLabsClientError.unauthorized
            case 429:
                throw PrimaLabsClientError.rateLimited
            case 400:
                throw PrimaLabsClientError.invalidRequest(message: nil)
            case 500...599:
                throw PrimaLabsClientError.server(statusCode: httpResponse.statusCode)
            default:
                throw PrimaLabsClientError.invalidResponse
            }
        } catch let error as PrimaLabsClientError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw PrimaLabsClientError.network
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw PrimaLabsClientError.decoding
        }
    }

    private func logRawResponse(path: String, data: Data, statusCode: Int) async {
        let maxBytes = 64 * 1024
        let captured = data.prefix(maxBytes)
        let body = String(data: captured, encoding: .utf8) ?? "<non-UTF8 response>"
        let suffix = data.count > maxBytes ? "\n[truncated after \(maxBytes) bytes]" : ""
        await diagnosticLogStore?.info("HTTP response GET \(path) status=\(statusCode) bytes=\(data.count)")
        await diagnosticLogStore?.debug("RAW HTTP RESPONSE BODY:\n\(body)\(suffix)")
    }

    /// PrimaLabs buckets are wall-clock labels in the requested timezone:
    /// `yyyy-MM-dd` for days, `yyyy-MM-dd'T'HH:mm` for hours. Full ISO
    /// timestamps are accepted as-is.
    internal static func bucketDate(from raw: String, timeZone: TimeZone) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: raw) { return date }

        let formatter = DateFormatter()
        formatter.calendar = UTCCalendar.gregorian
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = raw.contains("T") ? "yyyy-MM-dd'T'HH:mm" : "yyyy-MM-dd"
        return formatter.date(from: raw)
    }
}
