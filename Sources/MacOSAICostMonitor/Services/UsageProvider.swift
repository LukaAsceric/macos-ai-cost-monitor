import Foundation

public protocol UsageProvider: Sendable {
    func activity(for date: String, apiKey: String) async throws -> [ActivityItem]
}
