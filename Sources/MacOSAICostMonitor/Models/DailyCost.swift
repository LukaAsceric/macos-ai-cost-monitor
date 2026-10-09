import Foundation

public struct CostBreakdown: Codable, Sendable, Equatable, Identifiable {
    public let model: String
    public let provider: String
    /// The configured provider service the row was fetched from ("" in cached
    /// reports created before services were tracked). Excluded from coding so
    /// old caches keep decoding.
    public var service: String = ""
    public let usage: Decimal
    public let requests: Int
    public let promptTokens: Int
    public let completionTokens: Int
    public let reasoningTokens: Int

    public var id: String { "\(service)|\(model)|\(provider)" }

    public init(
        model: String,
        provider: String,
        service: String = "",
        usage: Decimal,
        requests: Int,
        promptTokens: Int,
        completionTokens: Int,
        reasoningTokens: Int
    ) {
        self.model = model
        self.provider = provider
        self.service = service
        self.usage = usage
        self.requests = requests
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.reasoningTokens = reasoningTokens
    }

    private enum CodingKeys: String, CodingKey {
        case model, provider, usage, requests, promptTokens, completionTokens, reasoningTokens
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
        aggregateRows(items.filter { $0.date == date }, reportDate: date)
    }

    public static func aggregateAll(_ items: [ActivityItem], reportDate: String) -> DailyCost {
        aggregateRows(items, reportDate: reportDate)
    }

    private static func aggregateRows(_ matching: [ActivityItem], reportDate: String) -> DailyCost {
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

            let key = "\(item.service)|\(item.model)|\(item.providerName)"
            let current = grouped[key] ?? CostBreakdown(
                model: item.model,
                provider: item.providerName,
                service: item.service,
                usage: .zero,
                requests: 0,
                promptTokens: 0,
                completionTokens: 0,
                reasoningTokens: 0
            )
            grouped[key] = CostBreakdown(
                model: current.model,
                provider: current.provider,
                service: current.service,
                usage: current.usage + item.usage,
                requests: current.requests + item.requests,
                promptTokens: current.promptTokens + item.promptTokens,
                completionTokens: current.completionTokens + item.completionTokens,
                reasoningTokens: current.reasoningTokens + (item.reasoningTokens ?? 0)
            )
        }

        return DailyCost(
            date: reportDate,
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

public extension Array where Element == CostBreakdown {
    /// Merges breakdown rows that share the same model across multiple providers
    /// into a single row. Used when the user opts out of splitting the model list
    /// by provider. Token and request counts are summed; the provider field becomes
    /// a sorted, de-duplicated list of the contributing providers.
    func groupedByModel() -> [CostBreakdown] {
        guard !isEmpty else { return [] }

        var merged: [String: CostBreakdown] = [:]
        for entry in self {
            if var existing = merged[entry.model] {
                var providers = existing.provider.split(separator: ", ").map(String.init)
                if !providers.contains(entry.provider) {
                    providers.append(entry.provider)
                }
                existing = CostBreakdown(
                    model: entry.model,
                    provider: providers.sorted().joined(separator: ", "),
                    service: existing.service == entry.service ? entry.service : "",
                    usage: existing.usage + entry.usage,
                    requests: existing.requests + entry.requests,
                    promptTokens: existing.promptTokens + entry.promptTokens,
                    completionTokens: existing.completionTokens + entry.completionTokens,
                    reasoningTokens: existing.reasoningTokens + entry.reasoningTokens
                )
                merged[entry.model] = existing
            } else {
                merged[entry.model] = entry
            }
        }

        return merged.values.sorted {
            if $0.usage == $1.usage { return $0.id < $1.id }
            return $0.usage > $1.usage
        }
    }

    /// Groups breakdown rows by the configured provider service and prepares the
    /// hierarchical "By provider" view: one group per service with the per-upstream
    /// provider split below it. Rows without a service (cached reports predating
    /// service tracking) fall back to grouping by provider name, which reproduces
    /// the previous flat layout.
    func groupedByService() -> [ProviderBreakdownGroup] {
        guard !isEmpty else { return [] }

        var groups: [String: [CostBreakdown]] = [:]
        for entry in self {
            let key = entry.service.isEmpty ? entry.provider : entry.service
            groups[key, default: []].append(entry)
        }

        return groups.map { service, rows in
            var merged: [String: CostBreakdown] = [:]
            for row in rows {
                let current = merged[row.provider] ?? CostBreakdown(
                    model: row.model,
                    provider: row.provider,
                    service: service,
                    usage: .zero,
                    requests: 0,
                    promptTokens: 0,
                    completionTokens: 0,
                    reasoningTokens: 0
                )
                merged[row.provider] = CostBreakdown(
                    model: current.model,
                    provider: current.provider,
                    service: service,
                    usage: current.usage + row.usage,
                    requests: current.requests + row.requests,
                    promptTokens: current.promptTokens + row.promptTokens,
                    completionTokens: current.completionTokens + row.completionTokens,
                    reasoningTokens: current.reasoningTokens + row.reasoningTokens
                )
            }
            let upstreams = merged.values.sorted {
                if $0.usage == $1.usage { return $0.provider < $1.provider }
                return $0.usage > $1.usage
            }
            return ProviderBreakdownGroup(
                service: service,
                usage: upstreams.reduce(.zero) { $0 + $1.usage },
                upstreams: upstreams
            )
        }
        .sorted {
            if $0.usage == $1.usage { return $0.service < $1.service }
            return $0.usage > $1.usage
        }
    }
}

/// One configured provider service with its per-upstream-provider split.
public struct ProviderBreakdownGroup: Identifiable, Equatable, Sendable {
    public let service: String
    public let usage: Decimal
    /// Rows per upstream provider. A routing service (for example OpenRouter)
    /// reports the routed providers here; a direct service reports itself.
    public let upstreams: [CostBreakdown]

    public var id: String { service }

    /// The upstream rows add information for routing services and whenever more
    /// than one upstream contributed; a single upstream equal to the service name
    /// would only repeat the group row.
    public var showsUpstreamBreakdown: Bool {
        guard let first = upstreams.first else { return false }
        return upstreams.count > 1 || first.provider != service
    }
}
