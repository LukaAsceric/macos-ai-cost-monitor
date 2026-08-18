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
        case .past24Hours, .today, .yesterday: return "1d"
        case .past48Hours: return "2d"
        case .pastWeek, .thisWeek, .previousWeek: return "1w"
        case .pastMonth, .thisMonth, .previousMonth: return "1mo"
        case .pastYear, .thisYear, .previousYear: return "1y"
        case .custom: return "⌘"
        case .latestAvailableDay: return "UTC"
        case .last30CompletedDays: return "30d"
        }
    }

    public var isSupported: Bool { true }

    public var analyticsGranularity: AnalyticsGranularity {
        switch self {
        case .past15Minutes, .past30Minutes:
            return .minute
        case .pastHour, .past3Hours, .past24Hours, .today:
            return .hour
        case .pastYear, .thisYear, .previousYear:
            return .month
        default:
            return .day
        }
    }

    public func absoluteWindow(
        now: Date,
        timeZone: TimeZone,
        customStart: Date?,
        customEnd: Date?
    ) -> ClosedRange<Date> {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.firstWeekday = 2
        calendar.locale = Locale(identifier: "en_US_POSIX")

        func startOfDay(_ date: Date) -> Date {
            calendar.startOfDay(for: date)
        }
        func add(_ component: Calendar.Component, value: Int, to date: Date) -> Date {
            calendar.date(byAdding: component, value: value, to: date) ?? date
        }

        switch self {
        case .past15Minutes:
            return add(.minute, value: -15, to: now)...now
        case .past30Minutes:
            return add(.minute, value: -30, to: now)...now
        case .pastHour:
            return add(.hour, value: -1, to: now)...now
        case .past3Hours:
            return add(.hour, value: -3, to: now)...now
        case .past24Hours:
            return add(.hour, value: -24, to: now)...now
        case .past48Hours:
            return add(.hour, value: -48, to: now)...now
        case .pastWeek:
            return add(.day, value: -7, to: now)...now
        case .pastMonth:
            return add(.month, value: -1, to: now)...now
        case .pastYear:
            return add(.year, value: -1, to: now)...now
        case .today:
            return startOfDay(now)...now
        case .yesterday:
            let start = startOfDay(add(.day, value: -1, to: now))
            let end = startOfDay(now)
            return start...end
        case .thisWeek:
            let weekday = calendar.component(.weekday, from: now)
            let daysFromMonday = (weekday + 5) % 7
            let start = startOfDay(add(.day, value: -daysFromMonday, to: now))
            return start...now
        case .previousWeek:
            let weekday = calendar.component(.weekday, from: now)
            let daysFromMonday = (weekday + 5) % 7
            let thisMonday = startOfDay(add(.day, value: -daysFromMonday, to: now))
            let previousMonday = add(.day, value: -7, to: thisMonday)
            return previousMonday...thisMonday
        case .thisMonth:
            let comps = calendar.dateComponents([.year, .month], from: now)
            let start = calendar.date(from: comps) ?? startOfDay(now)
            return start...now
        case .previousMonth:
            let comps = calendar.dateComponents([.year, .month], from: now)
            let thisMonth = calendar.date(from: comps) ?? startOfDay(now)
            let previous = add(.month, value: -1, to: thisMonth)
            return previous...thisMonth
        case .thisYear:
            let comps = calendar.dateComponents([.year], from: now)
            let start = calendar.date(from: comps) ?? startOfDay(now)
            return start...now
        case .previousYear:
            let comps = calendar.dateComponents([.year], from: now)
            let thisYear = calendar.date(from: comps) ?? startOfDay(now)
            let previous = add(.year, value: -1, to: thisYear)
            return previous...thisYear
        case .custom:
            let start = customStart ?? add(.day, value: -1, to: now)
            let end = customEnd ?? now
            return min(start, end)...max(start, end)
        case .latestAvailableDay:
            let start = UTCCalendar.startOfDay(add(.day, value: -1, to: now))
            return start...now
        case .last30CompletedDays:
            return add(.day, value: -30, to: now)...now
        }
    }

    /// Inclusive day offsets relative to the latest completed UTC day
    /// (0 = latest completed day, -1 = previous day, and so on).
    public func dayRange(reference completedDate: Date = Date()) -> ClosedRange<Int> {
        switch self {
        case .past15Minutes, .past30Minutes, .pastHour, .past3Hours, .past24Hours, .today:
            return 0...0
        case .yesterday, .past48Hours:
            return -1...0
        case .pastWeek:
            return -6...0
        case .pastMonth:
            return -29...0
        case .pastYear, .thisYear, .previousYear:
            return -365...0
        case .thisWeek:
            let start = utcCalendar.dateComponents([.weekday], from: completedDate).weekday ?? 1
            let daysSinceMonday = start - 2
            return (-daysSinceMonday)...0
        case .previousWeek:
            let start = utcCalendar.dateComponents([.weekday], from: completedDate).weekday ?? 1
            let daysSinceMonday = start - 2
            let previousStart = daysSinceMonday + 7
            let previousEnd = daysSinceMonday + 1
            return (-previousStart)...(-previousEnd)
        case .thisMonth:
            let day = utcCalendar.dateComponents([.day], from: completedDate).day ?? 1
            return (1 - day)...0
        case .previousMonth:
            guard let firstOfMonth = utcCalendar.date(from: utcCalendar.dateComponents([.year, .month], from: completedDate)),
                  let previousMonth = utcCalendar.date(byAdding: .month, value: -1, to: firstOfMonth),
                  let previousStart = utcCalendar.date(from: utcCalendar.dateComponents([.year, .month], from: previousMonth)),
                  let currentStart = utcCalendar.date(from: utcCalendar.dateComponents([.year, .month], from: completedDate)) else {
                return -29...0
            }
            let startOffset = utcCalendar.dateComponents([.day], from: previousStart, to: currentStart).day ?? 30
            let previousDays = utcCalendar.range(of: .day, in: .month, for: previousStart)?.count ?? 30
            return (-(startOffset + previousDays - 1))...(-startOffset)
        case .last30CompletedDays:
            return -29...0
        case .latestAvailableDay, .custom:
            return 0...0
        }
    }

    public var reportLabel: String {
        switch self {
        case .latestAvailableDay:
            return "Latest completed UTC day"
        case .last30CompletedDays:
            return "Last 30 completed UTC days"
        default:
            return title
        }
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    public var reportRange: ReportRange {
        self == .last30CompletedDays ? .last30Days : .latestAvailableDay
    }

    public enum Group: String, CaseIterable, Identifiable, Hashable {
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
        static let timeZoneIdentifier = "displayTimeZoneIdentifier"
        static let customStart = "customRangeStart"
        static let customEnd = "customRangeEnd"
        static let budgetEnabled = "budgetEnabled"
        static let budgetAmount = "budgetAmount"
        static let notifyOnBudget = "notifyOnBudget"
        static let showTokenDetails = "showTokenDetails"
        static let showRequestDetails = "showRequestDetails"
        static let showProviderDetails = "showProviderDetails"
        static let showFullBreakdown = "showFullBreakdown"
        static let useLocalCalendar = "useLocalCalendar"
        static let groupModelsAcrossProviders = "groupModelsAcrossProviders"
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

    @Published public var timeZoneIdentifier: String {
        didSet { defaults.set(timeZoneIdentifier, forKey: Keys.timeZoneIdentifier) }
    }

    @Published public var customStart: Date {
        didSet { defaults.set(customStart, forKey: Keys.customStart) }
    }

    @Published public var customEnd: Date {
        didSet { defaults.set(customEnd, forKey: Keys.customEnd) }
    }

    @Published public var budgetEnabled: Bool {
        didSet { defaults.set(budgetEnabled, forKey: Keys.budgetEnabled) }
    }

    @Published public var budgetAmount: Double {
        didSet { defaults.set(budgetAmount, forKey: Keys.budgetAmount) }
    }

    @Published public var notifyOnBudget: Bool {
        didSet { defaults.set(notifyOnBudget, forKey: Keys.notifyOnBudget) }
    }

    @Published public var showTokenDetails: Bool {
        didSet { defaults.set(showTokenDetails, forKey: Keys.showTokenDetails) }
    }

    @Published public var showRequestDetails: Bool {
        didSet { defaults.set(showRequestDetails, forKey: Keys.showRequestDetails) }
    }

    @Published public var showProviderDetails: Bool {
        didSet { defaults.set(showProviderDetails, forKey: Keys.showProviderDetails) }
    }

    @Published public var showFullBreakdown: Bool {
        didSet { defaults.set(showFullBreakdown, forKey: Keys.showFullBreakdown) }
    }

    @Published public var useLocalCalendar: Bool {
        didSet { defaults.set(useLocalCalendar, forKey: Keys.useLocalCalendar) }
    }

    @Published public var groupModelsAcrossProviders: Bool {
        didSet { defaults.set(groupModelsAcrossProviders, forKey: Keys.groupModelsAcrossProviders) }
    }

    public var displayTimeZone: TimeZone {
        if useLocalCalendar {
            return TimeZone(identifier: timeZoneIdentifier) ?? .current
        }
        return TimeZone(secondsFromGMT: 0) ?? .current
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
        timeZoneIdentifier = defaults.string(forKey: Keys.timeZoneIdentifier) ?? TimeZone.current.identifier
        let resolvedCustomEnd = defaults.object(forKey: Keys.customEnd) as? Date ?? Date()
        customEnd = resolvedCustomEnd
        customStart = defaults.object(forKey: Keys.customStart) as? Date ?? resolvedCustomEnd.addingTimeInterval(-86_400)
        budgetEnabled = defaults.object(forKey: Keys.budgetEnabled) as? Bool ?? false
        budgetAmount = defaults.object(forKey: Keys.budgetAmount) as? Double ?? 5
        notifyOnBudget = defaults.object(forKey: Keys.notifyOnBudget) as? Bool ?? true
        showTokenDetails = defaults.object(forKey: Keys.showTokenDetails) as? Bool ?? true
        showRequestDetails = defaults.object(forKey: Keys.showRequestDetails) as? Bool ?? true
        showProviderDetails = defaults.object(forKey: Keys.showProviderDetails) as? Bool ?? true
        showFullBreakdown = defaults.object(forKey: Keys.showFullBreakdown) as? Bool ?? false
        useLocalCalendar = defaults.object(forKey: Keys.useLocalCalendar) as? Bool ?? true
        groupModelsAcrossProviders = defaults.object(forKey: Keys.groupModelsAcrossProviders) as? Bool ?? false
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
