import Foundation

public protocol UsageProvider: Sendable {
    func activity(for date: String, apiKey: String) async throws -> [ActivityItem]
    func recentActivity(apiKey: String) async throws -> [ActivityItem]
}

public extension UsageProvider {
    func recentActivity(apiKey: String) async throws -> [ActivityItem] {
        try await activity(for: "", apiKey: apiKey)
    }
}
