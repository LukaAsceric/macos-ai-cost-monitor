import Foundation
import XCTest
@testable import MacOSAICostMonitor

@MainActor
final class ReportingPreferencesTests: XCTestCase {
    func test_providerCatalogHasOnlyOpenRouterEnabled() {
        XCTAssertEqual(ProviderOption.allCases.filter(\.isEnabled), [.openRouter])
    }

    func test_unsupportedTimeRangeFallsBackToLatestAvailableDay() {
        let defaults = UserDefaults(suiteName: "ReportingPreferencesTests.\(UUID().uuidString)")!
        let preferences = ReportingPreferences(defaults: defaults)

        preferences.timeRange = .past15Minutes

        XCTAssertEqual(preferences.timeRange, .latestAvailableDay)
        XCTAssertEqual(preferences.reportRange, .latestAvailableDay)
    }

    func test_supportedThirtyDayRangeMapsToLegacyReportRange() {
        let defaults = UserDefaults(suiteName: "ReportingPreferencesTests.\(UUID().uuidString)")!
        let preferences = ReportingPreferences(defaults: defaults)

        preferences.timeRange = .last30CompletedDays

        XCTAssertEqual(preferences.reportRange, .last30Days)
    }
}

final class ReportTimeRangeTests: XCTestCase {
    func testScreenshotGroupsContainExpectedOptions() {
        XCTAssertEqual(ReportTimeRange.options(in: .relative).count, 9)
        XCTAssertTrue(ReportTimeRange.options(in: .calendar).contains(.custom))
        XCTAssertEqual(ReportTimeRange.options(in: .supported), [.latestAvailableDay, .last30CompletedDays])
        XCTAssertFalse(ReportTimeRange.pastHour.isSupported)
    }
}
