import Foundation

public struct CostBreakdown: Codable, Sendable, Equatable, Identifiable {
    public let model: String
    public let provider: String
    public let usage: Decimal
    public let requests: Int
    public let promptTokens: Int
    public let completionTokens: Int
    public let reasoningTokens: Int

    public var id: String { "\(model)|\(provider)" }

    public init(
        model: String,
        provider: String,
        usage: Decimal,
        requests: Int,
        promptTokens: Int,
        completionTokens: Int,
        reasoningTokens: Int
    ) {
        self.model = model
        self.provider = provider
        self.usage = usage
        self.requests = requests
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.reasoningTokens = reasoningTokens
    }
}

public struct DailyCost: Codable, Sendable, Equatable {
    public let date: String
    public let usage: Decimal
    public let byokUsageInference: Decimal
    public let requests: Int
    public let promptTokens: Int
    public let completionTokens: Int
    public let reasoningTokens: Int
    public let breakdowns: [CostBreakdown]

    public init(
        date: String,
        usage: Decimal,
        byokUsageInference: Decimal,
        requests: Int,
        promptTokens: Int,
        completionTokens: Int,
        reasoningTokens: Int,
        breakdowns: [CostBreakdown]
    ) {
        self.date = date
        self.usage = usage
        self.byokUsageInference = byokUsageInference
        self.requests = requests
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.reasoningTokens = reasoningTokens
        self.breakdowns = breakdowns
    }

    public static func empty(for date: String) -> DailyCost {
        DailyCost(
            date: date,
            usage: .zero,
            byokUsageInference: .zero,
            requests: 0,
            promptTokens: 0,
            completionTokens: 0,
            reasoningTokens: 0,
            breakdowns: []
        )
    }
}

public enum ActivityAggregator {
    public static func aggregate(_ items: [ActivityItem], for date: String) -> DailyCost {
        let matching = items.filter { $0.date == date }
        var grouped: [String: CostBreakdown] = [:]
        var usage = Decimal.zero
        var byok = Decimal.zero
        var requests = 0
        var promptTokens = 0
        var completionTokens = 0
        var reasoningTokens = 0

        for item in matching {
            usage += item.usage
            byok += item.byokUsageInference ?? .zero
            requests += item.requests
            promptTokens += item.promptTokens
            completionTokens += item.completionTokens
            reasoningTokens += item.reasoningTokens ?? 0

            let key = "\(item.model)|\(item.providerName)"
            let current = grouped[key] ?? CostBreakdown(
                model: item.model,
                provider: item.providerName,
                usage: .zero,
                requests: 0,
                promptTokens: 0,
                completionTokens: 0,
                reasoningTokens: 0
            )
            grouped[key] = CostBreakdown(
                model: current.model,
                provider: current.provider,
                usage: current.usage + item.usage,
                requests: current.requests + item.requests,
                promptTokens: current.promptTokens + item.promptTokens,
                completionTokens: current.completionTokens + item.completionTokens,
                reasoningTokens: current.reasoningTokens + (item.reasoningTokens ?? 0)
            )
        }

        return DailyCost(
            date: date,
            usage: usage,
            byokUsageInference: byok,
            requests: requests,
            promptTokens: promptTokens,
            completionTokens: completionTokens,
            reasoningTokens: reasoningTokens,
            breakdowns: grouped.values.sorted {
                if $0.usage == $1.usage { return $0.id < $1.id }
                return $0.usage > $1.usage
            }
        )
    }
}
