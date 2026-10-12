import Foundation

/// Gateway wire schema; translated into provider-independent identities and capabilities.
struct GatewayAgentDTO: Decodable {
  let agent: String
  let defaultModel: String
  let models: [GatewayAgentModelDTO]
  var profile: AgentProfile {
    AgentProfile(
      id: agent, displayName: agent.capitalized, defaultModel: defaultModel,
      models: models.map {
        AgentModel(
          id: $0.modelId, displayName: $0.displayName,
          supportsImages: $0.imageInput)
      })
  }
}
struct GatewayAgentModelDTO: Decodable {
  let modelId: String
  let displayName: String
  let imageInput: Bool
}
struct GatewayAgentListDTO: Decodable {
  let agents: [GatewayAgentDTO]
}
