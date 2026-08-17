import Foundation
import Combine

public enum ReportRange: String, CaseIterable, Codable, Sendable, Identifiable {
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

@MainActor
public final class ReportingPreferences: ObservableObject {
    private enum Keys {
        static let reportRange = "reportRange"
        static let decimalPlaces = "decimalPlaces"
        static let refreshInterval = "refreshInterval"
        static let includeByok = "includeByokInHeadline"
    }

    private let defaults: UserDefaults

    @Published public var reportRange: ReportRange {
        didSet { defaults.set(reportRange.rawValue, forKey: Keys.reportRange) }
    }

    /// Maximum number of fractional digits shown for dollar values.
    /// Two digits remain the minimum so ordinary costs stay currency-like.
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

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        reportRange = ReportRange(rawValue: defaults.string(forKey: Keys.reportRange) ?? "") ?? .latestAvailableDay
        decimalPlaces = min(max(defaults.object(forKey: Keys.decimalPlaces) as? Int ?? 6, 2), 8)
        refreshInterval = defaults.object(forKey: Keys.refreshInterval) as? TimeInterval ?? 300
        includeByokInHeadline = defaults.object(forKey: Keys.includeByok) as? Bool ?? false
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
