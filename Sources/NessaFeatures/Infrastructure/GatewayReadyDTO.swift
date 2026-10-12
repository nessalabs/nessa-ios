import Foundation

/// Exact current ProductSessionReady wire boundary, separate from application values.
struct GatewayReadyDTO: Decodable {
  let snapshot: GatewaySessionSnapshot

  private enum Keys: String, CodingKey {
    case version, gatewayId, principalId, organizationId, membershipId, credentialId, audienceId
    case expiresAt, grants, methods
  }
  init(from decoder: Decoder) throws {
    try rejectUnknown(
      decoder,
      allowed: [
        "version", "gatewayId", "principalId", "organizationId", "membershipId", "credentialId",
        "audienceId", "expiresAt", "grants", "methods",
      ])
    let values = try decoder.container(keyedBy: Keys.self)
    guard try values.decode(UInt64.self, forKey: .version) == 1 else {
      throw NessaGatewayError.incompatibleProtocol
    }
    let identity = try GatewaySessionSnapshot.Identity(
      gatewayID: bounded(values.decode(String.self, forKey: .gatewayId)),
      principalID: bounded(values.decode(String.self, forKey: .principalId)),
      organizationID: bounded(values.decode(String.self, forKey: .organizationId)),
      membershipID: bounded(values.decode(String.self, forKey: .membershipId)),
      credentialID: bounded(values.decode(String.self, forKey: .credentialId)),
      audienceID: bounded(values.decode(String.self, forKey: .audienceId)))
    guard values.contains(.expiresAt) else { throw NessaGatewayError.invalidFrame }
    let expiry = try values.decodeIfPresent(UInt64.self, forKey: .expiresAt)
    guard expiry.map({ $0 <= 9_007_199_254_740_991 }) ?? true else {
      throw NessaGatewayError.invalidFrame
    }
    let grants = try values.decode([GrantDTO].self, forKey: .grants)
    let methods = try values.decode([String].self, forKey: .methods)
    guard grants.count <= 16, methods.count <= 62 else { throw NessaGatewayError.invalidFrame }
    snapshot = GatewaySessionSnapshot(
      identity: identity, expiresAt: expiry, grants: grants.map(\.value), methods: methods)
  }

  private struct GrantDTO: Decodable {
    let value: GatewaySessionSnapshot.Grant
    private enum Keys: String, CodingKey { case action, resource }
    init(from decoder: Decoder) throws {
      try rejectUnknown(decoder, allowed: ["action", "resource"])
      let values = try decoder.container(keyedBy: Keys.self)
      value = try GatewaySessionSnapshot.Grant(
        action: bounded(values.decode(String.self, forKey: .action)),
        resource: values.decode(ResourceDTO.self, forKey: .resource).value)
    }
  }
  private struct ResourceDTO: Decodable {
    let value: GatewaySessionSnapshot.Resource
    private enum Keys: String, CodingKey { case organizationId, id }
    init(from decoder: Decoder) throws {
      try rejectUnknown(decoder, allowed: ["organizationId", "id"])
      let values = try decoder.container(keyedBy: Keys.self)
      value = try GatewaySessionSnapshot.Resource(
        organizationID: bounded(values.decode(String.self, forKey: .organizationId)),
        id: bounded(values.decode(String.self, forKey: .id)))
    }
  }
}

private func bounded(_ text: String) throws -> String {
  guard (1...256).contains(text.unicodeScalars.count) else { throw NessaGatewayError.invalidFrame }
  return text
}
private struct WireKey: CodingKey {
  let stringValue: String
  let intValue: Int? = nil
  init?(stringValue: String) { self.stringValue = stringValue }
  init?(intValue: Int) { return nil }
}
private func rejectUnknown(_ decoder: Decoder, allowed: Set<String>) throws {
  let values = try decoder.container(keyedBy: WireKey.self)
  guard values.allKeys.allSatisfy({ allowed.contains($0.stringValue) }) else {
    throw NessaGatewayError.invalidFrame
  }
}
