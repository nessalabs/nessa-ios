import Foundation

/// Gateway wire schema; translated into provider-independent AgentProfile values.
struct GatewayAgentDTO: Decodable {
  let agent: String
  let defaultModel: String
}
struct GatewayAgentListDTO: Decodable {
  let agents: [GatewayAgentDTO]
}
