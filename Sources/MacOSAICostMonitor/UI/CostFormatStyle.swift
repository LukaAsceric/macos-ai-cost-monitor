import Foundation

public enum CostFormatStyle {
    public static func headline(_ value: Decimal, maximumFractionDigits: Int = 6) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = min(max(maximumFractionDigits, 2), 8)
        formatter.usesGroupingSeparator = true
        formatter.positivePrefix = "$"
        formatter.negativePrefix = "-$"
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "$0.00"
    }

    public static func tokens(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSNumber(value: value)) ?? "0"
    }
}
