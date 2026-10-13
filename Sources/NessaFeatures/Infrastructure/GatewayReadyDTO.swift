import Foundation

/// Exact current ProductSessionReady wire boundary, separate from application values.
struct GatewayReadyDTO: Decodable {
  let snapshot: GatewaySessionSnapshot

  private enum Keys: String, CodingKey {
    case version, gatewayId, principalId, organizationId, membershipId, credentialId, audienceId
    case expiresAt, grants, methods
  }
  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: Keys.self)
    guard try values.decode(UInt64.self, forKey: .version) == 1 else {
      throw NessaGatewayError.incompatibleProtocol
    }
    try validateGatewayWire(decoder, named: "ProductSessionReady")
    let identity = try GatewaySessionSnapshot.Identity(
      gatewayID: values.decode(String.self, forKey: .gatewayId),
      principalID: values.decode(String.self, forKey: .principalId),
      organizationID: values.decode(String.self, forKey: .organizationId),
      membershipID: values.decode(String.self, forKey: .membershipId),
      credentialID: values.decode(String.self, forKey: .credentialId),
      audienceID: values.decode(String.self, forKey: .audienceId))
    let expiry = try values.decodeIfPresent(UInt64.self, forKey: .expiresAt)
    let grants = try values.decode([GatewayGrantDTO].self, forKey: .grants)
    let methods = try values.decode([String].self, forKey: .methods)
    snapshot = GatewaySessionSnapshot(
      identity: identity, expiresAt: expiry, grants: grants.map(\.value), methods: methods)
  }

}

struct GatewayGrantDTO: Decodable {
  let value: GatewaySessionSnapshot.Grant
  private enum Keys: String, CodingKey { case action, resource }
  init(from decoder: Decoder) throws {
    try validateGatewayWire(decoder, named: "ProductGrant")
    let values = try decoder.container(keyedBy: Keys.self)
    value = try GatewaySessionSnapshot.Grant(
      action: values.decode(String.self, forKey: .action),
      resource: values.decode(GatewayResourceDTO.self, forKey: .resource).value)
  }
}
struct GatewayResourceDTO: Decodable {
  let value: GatewaySessionSnapshot.Resource
  private enum Keys: String, CodingKey { case organizationId, id }
  init(from decoder: Decoder) throws {
    try validateGatewayWire(decoder, named: "ProductResource")
    let values = try decoder.container(keyedBy: Keys.self)
    value = try GatewaySessionSnapshot.Resource(
      organizationID: values.decode(String.self, forKey: .organizationId),
      id: values.decode(String.self, forKey: .id))
  }
}
