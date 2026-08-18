import Foundation
import XCTest
@testable import MacOSAICostMonitor

final class UTCCalendarTests: XCTestCase {
    func test_parsesUtcDayStringsWithoutMainActor() {
        let monday = UTCCalendar.date(from: "2026-08-17")
        XCTAssertNotNil(monday)
        XCTAssertEqual(UTCCalendar.dayString(from: monday!), "2026-08-17")
    }

    func test_parsesIso8601WithAndWithoutFraction() {
        XCTAssertNotNil(UTCCalendar.parseISO8601("2026-08-16T22:00:00.000Z"))
        XCTAssertNotNil(UTCCalendar.parseISO8601("2026-08-17T20:59:02Z"))
        XCTAssertNotNil(UTCCalendar.parseISO8601("2026-08-17"))
    }

    func test_readableDayLabelDoesNotShiftTheUtcBucket() {
        // Parsed and formatted both in UTC, so the labels are timezone-stable.
        XCTAssertEqual(UTCCalendar.readableDayLabel(from: "2026-08-17"), "Mon, Aug 17, 2026")
        XCTAssertEqual(UTCCalendar.readableDayLabel(from: "2026-08-01"), "Sat, Aug 1, 2026")
    }

    func test_readableDayLabelReturnsInputWhenUnparsable() {
        XCTAssertEqual(UTCCalendar.readableDayLabel(from: "not-a-date"), "not-a-date")
    }
}
