import NessaFeatures

/// Ordinary module import verifies the public DI port has constructible values.
private struct IdentitySubstitute: AuthenticatedGatewaySessionProviding {
  let publication: AuthenticatedGatewaySession
  func authenticatedSession(for lease: GatewayConnectionLease) async throws
    -> AuthenticatedGatewaySession
  {
    guard lease == publication.connection else { throw NessaGatewayError.disconnected }
    return publication
  }
}

func verifyIdentitySubstitution() async throws {
  let lease = GatewayConnectionLease()
  let identity = GatewaySessionSnapshot.Identity(
    gatewayID: "gateway", principalID: "owner", organizationID: "org", membershipID: "membership",
    credentialID: "credential", audienceID: "audience")
  let grant = GatewaySessionSnapshot.Grant(
    action: "record.read", resource: .init(organizationID: "org", id: "gateway"))
  let snapshot = GatewaySessionSnapshot(
    identity: identity, expiresAt: nil, grants: [grant], methods: ["conversation.read"])
  let publication = AuthenticatedGatewaySession(connection: lease, snapshot: snapshot)
  let substitute: any AuthenticatedGatewaySessionProviding = IdentitySubstitute(
    publication: publication)
  guard try await substitute.authenticatedSession(for: lease) == publication else {
    throw NessaGatewayError.invalidFrame
  }
  print("PASS: external-module authenticated identity port substitution")
}
