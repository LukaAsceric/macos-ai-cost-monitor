import Foundation

public enum AnalyticsGranularity: String, Codable, Sendable {
    case minute
    case hour
    case day
    case week
    case month
}

public struct AnalyticsTimeRange: Equatable, Sendable {
    public let start: String
    public let end: String

    public init(start: String, end: String) {
        self.start = start
        self.end = end
    }
}

public struct AnalyticsQuery: Equatable, Sendable {
    public let metrics: [String]
    public let dimensions: [String]
    public let granularity: AnalyticsGranularity
    public let timeRange: AnalyticsTimeRange
    public let orderByField: String
    public let orderDirection: String
    public let topN: Int
    public let includeEnrichment: Bool

    public static let defaultMetrics = [
        "total_usage",
        "byok_usage",
        "request_count",
        "tokens_prompt",
        "tokens_completion"
    ]

    public static func make(
        range: ReportTimeRange,
        now: Date,
        timeZone: TimeZone,
        customStart: Date?,
        customEnd: Date?
    ) -> AnalyticsQuery {
        let window = range.absoluteWindow(now: now, timeZone: timeZone, customStart: customStart, customEnd: customEnd)
        return AnalyticsQuery(
            metrics: defaultMetrics,
            dimensions: ["model", "provider"],
            granularity: range.analyticsGranularity,
            timeRange: AnalyticsTimeRange(
                start: UTCCalendar.iso8601String(from: window.lowerBound),
                end: UTCCalendar.iso8601String(from: window.upperBound)
            ),
            orderByField: "date",
            orderDirection: "asc",
            topN: 10,
            includeEnrichment: true
        )
    }

    public func jsonObject() -> [String: Any] {
        [
            "metrics": metrics,
            "dimensions": dimensions,
            "granularity": granularity.rawValue,
            "time_range": [
                "start": timeRange.start,
                "end": timeRange.end
            ],
            "order_by": [
                "field": orderByField,
                "direction": orderDirection
            ],
            "topN": topN,
            "sortMetricDirection": "desc",
            "includeEnrichment": includeEnrichment
        ]
    }
}

public struct AnalyticsRow: Equatable, Sendable {
    public let timestamp: Date?
    public let model: String
    public let provider: String
    public let usage: Decimal
    public let byokUsage: Decimal
    public let requests: Int
    public let promptTokens: Int
    public let completionTokens: Int

    public init(
        timestamp: Date?,
        model: String,
        provider: String,
        usage: Decimal,
        byokUsage: Decimal,
        requests: Int,
        promptTokens: Int,
        completionTokens: Int
    ) {
        self.timestamp = timestamp
        self.model = model
        self.provider = provider
        self.usage = usage
        self.byokUsage = byokUsage
        self.requests = requests
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
    }

    public func asActivityItem() -> ActivityItem {
        ActivityItem(
            date: timestamp.map(UTCCalendar.dayString(from:)) ?? "",
            model: model,
            providerName: provider,
            usage: usage,
            byokUsageInference: byokUsage,
            requests: requests,
            promptTokens: promptTokens,
            completionTokens: completionTokens
        )
    }
}

public struct AnalyticsQueryResult: Equatable, Sendable {
    public let rows: [AnalyticsRow]
    public let truncated: Bool

    public init(rows: [AnalyticsRow], truncated: Bool) {
        self.rows = rows
        self.truncated = truncated
    }

    public var series: [CostSeriesPoint] {
        var grouped: [Date: Decimal] = [:]
        for row in rows {
            guard let timestamp = row.timestamp else { continue }
            grouped[timestamp, default: .zero] += row.usage
        }
        return grouped.keys.sorted().map { date in
            CostSeriesPoint(date: date, usage: grouped[date] ?? .zero)
        }
    }

    public func dailyCost(label: String) -> DailyCost {
        ActivityAggregator.aggregateAll(rows.map { $0.asActivityItem() }, reportDate: label)
    }
}

public enum AnalyticsResponseDecoder {
    public static func decode(_ data: Data) throws -> AnalyticsQueryResult {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any] else { throw OpenRouterClientError.decoding }
        let payload: [String: Any]
        if let nested = root["data"] as? [String: Any] {
            payload = nested
        } else {
            payload = root
        }
        let rowsObject = payload["data"] as? [[String: Any]] ?? []
        let metadata = payload["metadata"] as? [String: Any]
        let truncated = metadata?["truncated"] as? Bool ?? false
        let rows = rowsObject.compactMap(decodeRow)
        return AnalyticsQueryResult(rows: rows, truncated: truncated)
    }

    private static func decodeRow(_ raw: [String: Any]) -> AnalyticsRow? {
        let timestamp = firstDate(in: raw, keys: ["date__minute", "date__hour", "date__day", "date__week", "date__month", "date"])
        let model = string(raw["model"]) ?? "unknown"
        let provider = string(raw["provider"]) ?? string(raw["provider_name"]) ?? "OpenRouter"
        return AnalyticsRow(
            timestamp: timestamp,
            model: model,
            provider: provider,
            usage: decimal(raw["total_usage"]) ?? decimal(raw["usage"]) ?? .zero,
            byokUsage: decimal(raw["byok_usage"]) ?? decimal(raw["byok_usage_inference"]) ?? .zero,
            requests: int(raw["request_count"]) ?? int(raw["requests"]) ?? 0,
            promptTokens: int(raw["tokens_prompt"]) ?? int(raw["prompt_tokens"]) ?? 0,
            completionTokens: int(raw["tokens_completion"]) ?? int(raw["completion_tokens"]) ?? 0
        )
    }

    private static func firstDate(in raw: [String: Any], keys: [String]) -> Date? {
        for key in keys {
            if let value = string(raw[key]), let date = UTCCalendar.parseISO8601(value) {
                return date
            }
        }
        return nil
    }

    private static func string(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private static func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? Double { return Int(value) }
        if let value = value as? String { return Int(value) }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    private static func decimal(_ value: Any?) -> Decimal? {
        if let value = value as? Decimal { return value }
        if let value = value as? Double { return Decimal(value) }
        if let value = value as? Int { return Decimal(value) }
        if let value = value as? String { return Decimal(string: value) }
        if let value = value as? NSNumber { return Decimal(string: value.stringValue) }
        return nil
    }
}

public struct CostSeriesPoint: Codable, Sendable, Equatable, Identifiable {
    public let date: Date
    public let usage: Decimal
    public var id: Date { date }

    public init(date: Date, usage: Decimal) {
        self.date = date
        self.usage = usage
    }
}
