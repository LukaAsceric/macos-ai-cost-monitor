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
}
