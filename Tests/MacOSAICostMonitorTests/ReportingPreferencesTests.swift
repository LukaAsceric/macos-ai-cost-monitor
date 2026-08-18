import Foundation
import XCTest
@testable import MacOSAICostMonitor

final class ReportingPreferencesTests: XCTestCase {
    func test_unsupportedTimeRangeFallsBackToLatestAvailableDay() {
        let defaults = UserDefaults(suiteName: "ReportingPreferencesTests.\(UUID().uuidString)")!
        let preferences = ReportingPreferences(defaults: defaults)

        preferences.timeRange = .past15Minutes

        XCTAssertEqual(preferences.timeRange, .past15Minutes)
        XCTAssertEqual(preferences.timeRange.analyticsGranularity, .minute)
    }

    func test_supportedThirtyDayRangeMapsToLegacyReportRange() {
        let defaults = UserDefaults(suiteName: "ReportingPreferencesTests.\(UUID().uuidString)")!
        let preferences = ReportingPreferences(defaults: defaults)

        preferences.timeRange = .last30CompletedDays

        XCTAssertEqual(preferences.reportRange, .last30Days)
    }

    func test_menuLabelsRemainDistinctForEquivalentDurationRanges() {
        let ranges: [ReportTimeRange] = [
            .past24Hours, .today, .yesterday,
            .pastWeek, .thisWeek, .previousWeek,
            .pastMonth, .thisMonth, .previousMonth,
            .pastYear, .thisYear, .previousYear
        ]

        XCTAssertEqual(Set(ranges.map(\.menuLabel)).count, ranges.count)
        XCTAssertEqual(ReportTimeRange.today.menuLabel, "Today")
        XCTAssertEqual(ReportTimeRange.past24Hours.menuLabel, "Past 24 Hours")
        XCTAssertEqual(ReportTimeRange.previousWeek.menuLabel, "Previous Week")
        XCTAssertEqual(ReportTimeRange.previousMonth.menuLabel, "Previous Month")
        XCTAssertEqual(ReportTimeRange.previousYear.menuLabel, "Previous Year")
    }
}
