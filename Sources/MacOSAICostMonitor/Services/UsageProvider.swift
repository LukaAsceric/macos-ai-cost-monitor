import Foundation

public protocol UsageProvider: Sendable {
    func activity(for date: String, apiKey: String) async throws -> [ActivityItem]
    func recentActivity(apiKey: String) async throws -> [ActivityItem]
    func recentActivity(apiKey: String, captureRawResponse: Bool) async throws -> [ActivityItem]
}

public extension UsageProvider {
    func recentActivity(apiKey: String) async throws -> [ActivityItem] {
        try await activity(for: "", apiKey: apiKey)
    }

    func recentActivity(apiKey: String, captureRawResponse: Bool) async throws -> [ActivityItem] {
        try await recentActivity(apiKey: apiKey)
    }
}
