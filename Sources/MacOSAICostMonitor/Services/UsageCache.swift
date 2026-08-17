import Foundation

public struct CachedUsage: Codable, Sendable, Equatable {
    public let version: Int
    public let cost: DailyCost
    public let fetchedAt: Date
    public let hasActivity: Bool
    public let previousCost: DailyCost?

    public init(
        version: Int = 1,
        cost: DailyCost,
        fetchedAt: Date,
        hasActivity: Bool = true,
        previousCost: DailyCost? = nil
    ) {
        self.version = version
        self.cost = cost
        self.fetchedAt = fetchedAt
        self.hasActivity = hasActivity
        self.previousCost = previousCost
    }

    private enum CodingKeys: String, CodingKey {
        case version, cost, fetchedAt, hasActivity, previousCost
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        cost = try container.decode(DailyCost.self, forKey: .cost)
        fetchedAt = try container.decode(Date.self, forKey: .fetchedAt)
        hasActivity = try container.decodeIfPresent(Bool.self, forKey: .hasActivity) ?? true
        previousCost = try container.decodeIfPresent(DailyCost.self, forKey: .previousCost)
    }
}

public protocol CostCache: Sendable {
    func load() -> CachedUsage?
    func save(_ value: CachedUsage) throws
}

public enum UsageCacheError: Error, Equatable, Sendable {
    case couldNotCreateDirectory
    case couldNotEncode
    case couldNotWrite

    public var userMessage: String {
        "The usage cache could not be updated; the live result is still available."
    }
}

public final class UsageCache: CostCache, @unchecked Sendable {
    private let fileURL: URL

    public init(fileURL: URL = UsageCache.defaultURL()) {
        self.fileURL = fileURL
    }

    public func load() -> CachedUsage? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        guard let value = try? decoder.decode(CachedUsage.self, from: data), value.version == 1 else {
            return nil
        }
        return value
    }

    public func save(_ value: CachedUsage) throws {
        let directory = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            throw UsageCacheError.couldNotCreateDirectory
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(value)
        } catch {
            throw UsageCacheError.couldNotEncode
        }

        do {
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            throw UsageCacheError.couldNotWrite
        }
    }

    public static func defaultURL(fileManager: FileManager = .default) -> URL {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("MacOSAICostMonitor/cache.json")
    }
}
