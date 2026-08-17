import Combine
import Foundation

public enum ProviderOption: String, CaseIterable, Codable, Sendable, Identifiable, Hashable {
    case openRouter
    case openAI
    case anthropic
    case googleAI
    case mistral
    case groq
    case xAI
    case togetherAI
    case fireworks
    case deepSeek
    case cohere
    case perplexity

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .openRouter: return "OpenRouter"
        case .openAI: return "OpenAI"
        case .anthropic: return "Anthropic"
        case .googleAI: return "Google AI"
        case .mistral: return "Mistral"
        case .groq: return "Groq"
        case .xAI: return "xAI"
        case .togetherAI: return "Together AI"
        case .fireworks: return "Fireworks AI"
        case .deepSeek: return "DeepSeek"
        case .cohere: return "Cohere"
        case .perplexity: return "Perplexity"
        }
    }

    public var isEnabled: Bool { self == .openRouter }
}

public enum ReportRange: String, CaseIterable, Codable, Sendable, Identifiable, Hashable {
    case latestAvailableDay
    case last30Days

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .latestAvailableDay: return "Latest available day"
        case .last30Days: return "Last 30 completed days"
        }
    }
}

public enum ReportTimeRange: String, CaseIterable, Codable, Sendable, Identifiable, Hashable {
    case past15Minutes
    case past30Minutes
    case pastHour
    case past3Hours
    case past24Hours
    case past48Hours
    case pastWeek
    case pastMonth
    case pastYear
    case today
    case yesterday
    case thisWeek
    case previousWeek
    case thisMonth
    case previousMonth
    case thisYear
    case previousYear
    case custom
    case latestAvailableDay
    case last30CompletedDays

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .past15Minutes: return "Past 15 Minutes"
        case .past30Minutes: return "Past 30 Minutes"
        case .pastHour: return "Past 1 Hour"
        case .past3Hours: return "Past 3 Hours"
        case .past24Hours: return "Past 24 Hours"
        case .past48Hours: return "Past 48 Hours"
        case .pastWeek: return "Past 1 Week"
        case .pastMonth: return "Past 1 Month"
        case .pastYear: return "Past 1 Year"
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .thisWeek: return "This Week"
        case .previousWeek: return "Previous Week"
        case .thisMonth: return "This Month"
        case .previousMonth: return "Previous Month"
        case .thisYear: return "This Year"
        case .previousYear: return "Previous Year"
        case .custom: return "Custom range…"
        case .latestAvailableDay: return "Latest available completed UTC day"
        case .last30CompletedDays: return "Last 30 completed UTC days"
        }
    }

    public var badge: String {
        switch self {
        case .past15Minutes: return "15m"
        case .past30Minutes: return "30m"
        case .pastHour: return "1h"
        case .past3Hours: return "3h"
        case .past24Hours, .today: return "1d"
        case .past48Hours: return "2d"
        case .pastWeek, .thisWeek, .previousWeek: return "1w"
        case .pastMonth, .thisMonth, .previousMonth: return "1mo"
        case .pastYear, .thisYear, .previousYear: return "1y"
        case .custom: return "⌘"
        case .latestAvailableDay: return "UTC"
        case .last30CompletedDays: return "30d"
        }
    }

    public var isSupported: Bool {
        self == .latestAvailableDay || self == .last30CompletedDays
    }

    public var reportRange: ReportRange {
        self == .last30CompletedDays ? .last30Days : .latestAvailableDay
    }

    public enum Group: String, CaseIterable, Identifiable {
        case relative
        case calendar
        case supported

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .relative: return "Relative ranges"
            case .calendar: return "Calendar ranges"
            case .supported: return "Available from OpenRouter"
            }
        }
    }

    public static func options(in group: Group) -> [ReportTimeRange] {
        switch group {
        case .relative:
            return [.past15Minutes, .past30Minutes, .pastHour, .past3Hours, .past24Hours, .past48Hours, .pastWeek, .pastMonth, .pastYear]
        case .calendar:
            return [.today, .yesterday, .thisWeek, .previousWeek, .thisMonth, .previousMonth, .thisYear, .previousYear, .custom]
        case .supported:
            return [.latestAvailableDay, .last30CompletedDays]
        }
    }
}

@MainActor
public final class ReportingPreferences: ObservableObject {
    private enum Keys {
        static let provider = "provider"
        static let reportRange = "reportRange"
        static let timeRange = "timeRange"
        static let decimalPlaces = "decimalPlaces"
        static let refreshInterval = "refreshInterval"
        static let includeByok = "includeByokInHeadline"
        static let captureRawHTTPResponses = "captureRawHTTPResponses"
    }

    private let defaults: UserDefaults

    @Published public var provider: ProviderOption {
        didSet { defaults.set(provider.rawValue, forKey: Keys.provider) }
    }

    @Published public var reportRange: ReportRange {
        didSet { defaults.set(reportRange.rawValue, forKey: Keys.reportRange) }
    }

    @Published public var timeRange: ReportTimeRange {
        didSet {
            guard timeRange.isSupported else {
                timeRange = .latestAvailableDay
                return
            }
            reportRange = timeRange.reportRange
            defaults.set(timeRange.rawValue, forKey: Keys.timeRange)
        }
    }

    @Published public var decimalPlaces: Int {
        didSet {
            let clamped = min(max(decimalPlaces, 2), 8)
            if decimalPlaces != clamped {
                decimalPlaces = clamped
            }
            defaults.set(clamped, forKey: Keys.decimalPlaces)
        }
    }

    @Published public var refreshInterval: TimeInterval {
        didSet { defaults.set(refreshInterval, forKey: Keys.refreshInterval) }
    }

    @Published public var includeByokInHeadline: Bool {
        didSet { defaults.set(includeByokInHeadline, forKey: Keys.includeByok) }
    }

    @Published public var captureRawHTTPResponses: Bool {
        didSet { defaults.set(captureRawHTTPResponses, forKey: Keys.captureRawHTTPResponses) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        provider = ProviderOption(rawValue: defaults.string(forKey: Keys.provider) ?? "") ?? .openRouter
        let legacyRange = ReportRange(rawValue: defaults.string(forKey: Keys.reportRange) ?? "") ?? .latestAvailableDay
        let savedTimeRange = ReportTimeRange(rawValue: defaults.string(forKey: Keys.timeRange) ?? "")
        let resolvedTimeRange = savedTimeRange ?? (legacyRange == .last30Days ? .last30CompletedDays : .latestAvailableDay)
        timeRange = resolvedTimeRange
        reportRange = resolvedTimeRange.reportRange
        decimalPlaces = min(max(defaults.object(forKey: Keys.decimalPlaces) as? Int ?? 6, 2), 8)
        refreshInterval = defaults.object(forKey: Keys.refreshInterval) as? TimeInterval ?? 300
        includeByokInHeadline = defaults.object(forKey: Keys.includeByok) as? Bool ?? false
        captureRawHTTPResponses = defaults.object(forKey: Keys.captureRawHTTPResponses) as? Bool ?? false
    }

    public var refreshIntervalLabel: String {
        switch refreshInterval {
        case 60: return "Every minute"
        case 300: return "Every 5 minutes"
        case 900: return "Every 15 minutes"
        case 1800: return "Every 30 minutes"
        default: return "Every \(Int(refreshInterval / 60)) minutes"
        }
    }
}
