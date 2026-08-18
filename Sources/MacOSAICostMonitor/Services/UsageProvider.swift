import Foundation

public protocol UsageProvider: Sendable {
    func activity(for date: String, apiKey: String) async throws -> [ActivityItem]
    func recentActivity(apiKey: String) async throws -> [ActivityItem]
    func recentActivity(apiKey: String, captureRawResponse: Bool) async throws -> [ActivityItem]
    func queryAnalytics(_ query: AnalyticsQuery, apiKey: String, captureRawResponse: Bool) async throws -> AnalyticsQueryResult
    func credits(apiKey: String, captureRawResponse: Bool) async throws -> OpenRouterCredits
}

public extension UsageProvider {
    func recentActivity(apiKey: String) async throws -> [ActivityItem] {
        try await activity(for: "", apiKey: apiKey)
    }

    func recentActivity(apiKey: String, captureRawResponse: Bool) async throws -> [ActivityItem] {
        try await recentActivity(apiKey: apiKey)
    }

    func queryAnalytics(_ query: AnalyticsQuery, apiKey: String, captureRawResponse: Bool) async throws -> AnalyticsQueryResult {
        let items = try await recentActivity(apiKey: apiKey, captureRawResponse: captureRawResponse)
        return AnalyticsQueryResult(
            rows: items.map {
                AnalyticsRow(
                    timestamp: UTCCalendar.date(from: $0.date),
                    model: $0.model,
                    provider: $0.providerName,
                    usage: $0.usage,
                    byokUsage: $0.byokUsageInference ?? .zero,
                    requests: $0.requests,
                    promptTokens: $0.promptTokens,
                    completionTokens: $0.completionTokens
                )
            },
            truncated: false
        )
    }

    func credits(apiKey: String, captureRawResponse: Bool) async throws -> OpenRouterCredits {
        throw OpenRouterClientError.invalidResponse
    }
}
