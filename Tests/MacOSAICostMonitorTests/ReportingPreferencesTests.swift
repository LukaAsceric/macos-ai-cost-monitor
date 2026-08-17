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

    func testDayRangesMapToUtcDayOffsets() throws {
        // 2026-08-17 is a Monday. The reference is the latest completed UTC day.
        let monday = try XCTUnwrap(CostMonitorModel.utcDate(from: "2026-08-17"))

        XCTAssertEqual(ReportTimeRange.yesterday.dayRange(reference: monday), -1...0)
        XCTAssertEqual(ReportTimeRange.pastWeek.dayRange(reference: monday), -6...0)
        XCTAssertEqual(ReportTimeRange.thisWeek.dayRange(reference: monday), 0...0) // Monday = week start
        XCTAssertEqual(ReportTimeRange.previousWeek.dayRange(reference: monday), -7...(-1))
    }

    func testDayRangePreviousAndThisMonth() throws {
        let reference = try XCTUnwrap(CostMonitorModel.utcDate(from: "2026-08-17"))
        let august = ReportTimeRange.thisMonth.dayRange(reference: reference)
        XCTAssertEqual(august, -16...0) // 17th of the month

        let july = ReportTimeRange.previousMonth.dayRange(reference: reference)
        // July 1 … July 31, relative to Aug 17
        XCTAssertEqual(july, -47...(-17))
    }
}
