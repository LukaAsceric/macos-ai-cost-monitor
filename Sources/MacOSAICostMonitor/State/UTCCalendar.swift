import Foundation

public enum UTCCalendar {
    public static var gregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 2
        return calendar
    }

    public static func date(from string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = gregorian
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)
    }

    public static func dayString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = gregorian
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    public static func iso8601String(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }

    public static func parseISO8601(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        withFraction.timeZone = TimeZone(secondsFromGMT: 0)
        if let date = withFraction.date(from: string) { return date }

        let withoutFraction = ISO8601DateFormatter()
        withoutFraction.formatOptions = [.withInternetDateTime]
        withoutFraction.timeZone = TimeZone(secondsFromGMT: 0)
        if let date = withoutFraction.date(from: string) { return date }

        if let day = date(from: String(string.prefix(10))) {
            return day
        }
        return nil
    }

    public static func startOfDay(_ date: Date) -> Date {
        gregorian.startOfDay(for: date)
    }

    public static func dayOffset(from date: Date) -> Int {
        gregorian.dateComponents([.day], from: Date(timeIntervalSince1970: 0), to: startOfDay(date)).day ?? 0
    }
}
