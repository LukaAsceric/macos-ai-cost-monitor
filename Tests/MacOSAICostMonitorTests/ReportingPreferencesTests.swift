import Foundation
import XCTest
@testable import MacOSAICostMonitor

@MainActor
final class ReportingPreferencesTests: XCTestCase {
    func test_primalabsProviderIsEnabledWithDedicatedCredentialCopy() {
        XCTAssertEqual(ProviderOption.primalabs.title, "PrimaLabs")
        XCTAssertTrue(ProviderOption.primalabs.isEnabled)
        XCTAssertEqual(ProviderOption.primalabs.keychainAccount, "primalabs-dashboard-token")
        XCTAssertEqual(ProviderOption.openRouter.keychainAccount, "openrouter-management-key")
        XCTAssertFalse(ProviderOption.openAI.isEnabled)
        XCTAssertEqual(ProviderOption.primalabs.credentialPlaceholder, "Bearer token")
        XCTAssertEqual(ProviderOption.openRouter.credentialPlaceholder, "Management API key")
    }

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

    func test_dialogTimeRangesDefaultToAllAndPersistUserSelection() {
        let suiteName = "ReportingPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = ReportingPreferences(defaults: defaults)
        XCTAssertEqual(preferences.dialogTimeRanges, Set(ReportTimeRange.allCases))

        preferences.setDialogTimeRange(.today, enabled: false)

        XCTAssertFalse(preferences.dialogTimeRanges.contains(.today))
        XCTAssertEqual(defaults.array(forKey: "dialogTimeRanges") as? [String], preferences.dialogTimeRanges.map(\.rawValue).sorted())

        let restored = ReportingPreferences(defaults: defaults)
        XCTAssertFalse(restored.dialogTimeRanges.contains(.today))
    }

    func test_dialogTimeRangesCannotBeDisabledCompletely() {
        let suiteName = "ReportingPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = ReportingPreferences(defaults: defaults)
        for range in ReportTimeRange.allCases {
            preferences.setDialogTimeRange(range, enabled: false)
        }

        XCTAssertEqual(preferences.dialogTimeRanges.count, 1)
    }

    func test_minuteLevelRangesAreProviderDependent() {
        XCTAssertFalse(ReportTimeRange.past15Minutes.isSupported(for: .primalabs))
        XCTAssertFalse(ReportTimeRange.past30Minutes.isSupported(for: .primalabs))
        XCTAssertTrue(ReportTimeRange.pastHour.isSupported(for: .primalabs))
        XCTAssertTrue(ReportTimeRange.today.isSupported(for: .primalabs))
        XCTAssertTrue(ReportTimeRange.pastYear.isSupported(for: .primalabs))
        XCTAssertTrue(ReportTimeRange.past15Minutes.isSupported(for: .openRouter))
    }

    func test_availableTimeRangesFollowTheSelectedProvider() {
        let suiteName = "ReportingPreferencesTests.ranges.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = ReportingPreferences(defaults: defaults)

        preferences.provider = .openRouter
        XCTAssertTrue(preferences.availableTimeRanges.contains(.past15Minutes))

        preferences.provider = .primalabs
        XCTAssertFalse(preferences.availableTimeRanges.contains(.past15Minutes))
        XCTAssertFalse(preferences.availableTimeRanges.contains(.past30Minutes))
        XCTAssertTrue(preferences.availableTimeRanges.contains(.pastHour))
        XCTAssertTrue(preferences.availableTimeRanges.contains(.today))
    }

    func test_switchingToPrimalabsFallsBackFromMinuteLevelRange() {
        let suiteName = "ReportingPreferencesTests.fallback.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = ReportingPreferences(defaults: defaults)

        preferences.provider = .openRouter
        preferences.timeRange = .past30Minutes
        XCTAssertEqual(preferences.timeRange, .past30Minutes)

        preferences.provider = .primalabs
        XCTAssertEqual(preferences.timeRange, .latestAvailableDay)
    }

    func test_aggregationOffersOnlyRangesEveryProviderSupports() {
        let suiteName = "ReportingPreferencesTests.rangesAggregate.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = ReportingPreferences(defaults: defaults)

        preferences.provider = .openRouter
        preferences.timeRange = .past15Minutes
        XCTAssertEqual(preferences.timeRange, .past15Minutes)

        preferences.aggregateProviders = true
        XCTAssertEqual(preferences.timeRange, .latestAvailableDay)
        XCTAssertFalse(preferences.availableTimeRanges.contains(.past15Minutes))
    }

    func test_aggregateProvidersDefaultsToOffAndPersists() {
        let suiteName = "ReportingPreferencesTests.aggregate.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let first = ReportingPreferences(defaults: defaults)
        XCTAssertFalse(first.aggregateProviders)

        first.aggregateProviders = true
        XCTAssertTrue(ReportingPreferences(defaults: defaults).aggregateProviders)
    }

    func test_newPreferencesDefaultToTodayAndPersistTheLastSelectedRange() {
        let suiteName = "ReportingPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = ReportingPreferences(defaults: defaults)

        XCTAssertEqual(preferences.timeRange, .today)

        preferences.timeRange = .previousMonth

        let restored = ReportingPreferences(defaults: defaults)
        XCTAssertEqual(restored.timeRange, .previousMonth)
    }
}
