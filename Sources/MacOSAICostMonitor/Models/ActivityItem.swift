import Foundation

public struct ActivityItem: Codable, Sendable, Equatable {
    public let date: String
    public let model: String
    public let modelPermaslug: String?
    public let endpointID: String?
    public let providerName: String
    public let usage: Decimal
    public let byokUsageInference: Decimal?
    public let requests: Int
    public let promptTokens: Int
    public let completionTokens: Int
    public let reasoningTokens: Int?

    public init(
        date: String,
        model: String,
        modelPermaslug: String? = nil,
        endpointID: String? = nil,
        providerName: String,
        usage: Decimal,
        byokUsageInference: Decimal? = nil,
        requests: Int,
        promptTokens: Int,
        completionTokens: Int,
        reasoningTokens: Int? = nil
    ) {
        self.date = date
        self.model = model
        self.modelPermaslug = modelPermaslug
        self.endpointID = endpointID
        self.providerName = providerName
        self.usage = usage
        self.byokUsageInference = byokUsageInference
        self.requests = requests
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.reasoningTokens = reasoningTokens
    }

    private enum CodingKeys: String, CodingKey {
        case date
        case model
        case modelPermaslug = "model_permaslug"
        case endpointID = "endpoint_id"
        case providerName = "provider_name"
        case usage
        case byokUsageInference = "byok_usage_inference"
        case requests
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case reasoningTokens = "reasoning_tokens"
    }
}
