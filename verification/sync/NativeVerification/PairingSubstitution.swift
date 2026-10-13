import Foundation
import NessaFeatures

/// Compile and exercise the public pairing port without native or infrastructure handles.
private struct PairingSubstitute: GatewayPairingManaging {
  let source: AuthenticatedGatewaySession
  let status: GatewayPairingStatus
  private func receipt<T: Sendable>(_ value: T, on lease: GatewayConnectionLease) throws
    -> GatewayPairingReceipt<T>
  {
    guard lease == source.connection else { throw NessaGatewayError.disconnected }
    return .init(source: source, value: value)
  }
  func createDevice(on lease: GatewayConnectionLease) async throws -> GatewayPairingReceipt<
    GatewayPairingCreated
  > {
    try receipt(.init(code: "ABCD-EFGH", status: status), on: lease)
  }
  func pairingStatus(_ invitation: Data, on lease: GatewayConnectionLease) async throws
    -> GatewayPairingReceipt<GatewayPairingStatus>
  {
    try receipt(status, on: lease)
  }
  func approvePairing(_ invitation: Data, deviceKey: Data, on lease: GatewayConnectionLease)
    async throws -> GatewayPairingReceipt<GatewayPairingApproval>
  {
    try receipt(.init(status: status, activationStopped: .permanent), on: lease)
  }
  func cancelPairing(_ invitation: Data, on lease: GatewayConnectionLease) async throws
    -> GatewayPairingReceipt<GatewayPairingStatus>
  {
    try receipt(status, on: lease)
  }
  func pendingPairings(on lease: GatewayConnectionLease) async throws -> GatewayPairingReceipt<
    [GatewayPairingStatus]
  > {
    try receipt([status], on: lease)
  }
}
func verifyPairingSubstitution() async throws {
  let lease = GatewayConnectionLease()
  let grant = GatewaySessionSnapshot.Grant(
    action: "conversation.read", resource: .init(organizationID: "org", id: "gateway"))
  let snapshot = GatewaySessionSnapshot(
    identity: .init(
      gatewayID: "gateway", principalID: "owner", organizationID: "org", membershipID: "membership",
      credentialID: "credential", audienceID: "audience"), expiresAt: nil, grants: [grant],
    methods: ["pairing.status"])
  let source = AuthenticatedGatewaySession(connection: lease, snapshot: snapshot)
  let status = GatewayPairingStatus(
    invitationID: Data(0..<16), consentID: Data(16..<32), generation: UInt64.max,
    consentClass: "gateway-conversation-read", grant: grant, createdAtMs: 0,
    expiresAtMs: UInt64.max, phase: .terminal, claimedDeviceKey: Data(0..<32),
    credentialID: "credential", receiver: .init(id: "receiver", accessEpoch: UInt64.max),
    terminal: .init(cause: .restarted, initiator: .system), cleanupPending: true)
  let substitute: any GatewayPairingManaging = PairingSubstitute(source: source, status: status)
  guard try await substitute.createDevice(on: lease).value.status == status,
    try await substitute.pairingStatus(status.invitationID, on: lease).source == source,
    try await substitute.approvePairing(status.invitationID, deviceKey: Data(0..<32), on: lease)
      .value.activationStopped == .permanent,
    try await substitute.cancelPairing(status.invitationID, on: lease).value == status,
    try await substitute.pendingPairings(on: lease).value == [status]
  else { throw NessaGatewayError.invalidFrame }
  let rejection = GatewayPairingRejection(
    code: "forbidden", diagnostic: "fixture", details: Data("null".utf8))
  let failure = GatewayPairingOperationFailure(source: source, underlying: rejection)
  guard failure.source == source, failure.underlying is GatewayPairingRejection else {
    throw NessaGatewayError.invalidFrame
  }
  print("PASS: external-module pairing DI values and original-source failure substitution")
}
