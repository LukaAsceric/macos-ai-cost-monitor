import Combine
import Foundation

public enum LogLevel: String, CaseIterable, Codable, Sendable, Identifiable, Hashable {
    case debug
    case info
    case warning
    case error

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .debug: return "Debug"
        case .info: return "Info"
        case .warning: return "Warning"
        case .error: return "Error"
        }
    }
}

public struct LogEntry: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let date: Date
    public let level: LogLevel
    public let message: String

    public init(id: UUID = UUID(), date: Date = Date(), level: LogLevel, message: String) {
        self.id = id
        self.date = date
        self.level = level
        self.message = message
    }

    public var line: String {
        "[\(date.formatted(date: .omitted, time: .standard))] [\(level.title.uppercased())] \(AppLogStore.redactForExport(message))"
    }
}

@MainActor
public final class AppLogStore: ObservableObject {
    public static let defaultCapacity = 500

    @Published public private(set) var entries: [LogEntry] = []
    private let capacity: Int
    private let now: @Sendable () -> Date

    public init(capacity: Int = AppLogStore.defaultCapacity, now: @escaping @Sendable () -> Date = { Date() }) {
        self.capacity = max(1, capacity)
        self.now = now
    }

    public func log(_ level: LogLevel, _ message: String) {
        let entry = LogEntry(date: now(), level: level, message: Self.redact(message))
        entries.append(entry)
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
    }

    public func clear() {
        entries.removeAll(keepingCapacity: true)
    }

    internal func text(for entries: [LogEntry]? = nil) -> String {
        (entries ?? self.entries).map(\.line).joined(separator: "\n")
    }

    private static func redact(_ message: String) -> String {
        redactForExport(message)
    }

    nonisolated public static func redactForExport(_ message: String) -> String {
        var result = message
        let patterns = [
            "(?i)bearer\\s+[^\\s]+",
            "(?i)sk-or-v1-[A-Za-z0-9_-]+",
            "(?i)(api[_-]?key|token|password|secret)\\s*[:=]\\s*[^\\s,;]+"
        ]

        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = expression.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: "[REDACTED]"
            )
        }
        return result
    }
}

public extension AppLogStore {
    func debug(_ message: String) { log(.debug, message) }
    func info(_ message: String) { log(.info, message) }
    func warning(_ message: String) { log(.warning, message) }
    func error(_ message: String) { log(.error, message) }
}
