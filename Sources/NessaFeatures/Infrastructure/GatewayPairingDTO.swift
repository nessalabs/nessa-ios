import Foundation

struct GatewayPairingStatusDTO: Decodable {
  let value: GatewayPairingStatus
  private enum Keys: String, CodingKey {
    case invitationId, consentId, generation, `class`, grant, createdAtMs, expiresAtMs, phase
    case claimedDeviceKey, credentialId, receiver, terminal, cleanupPending
  }
  init(from decoder: Decoder) throws {
    try validateGatewayWire(decoder, named: "PairingOwnerStatus")
    let v = try decoder.container(keyedBy: Keys.self)
    value = try GatewayPairingStatus(
      invitationID: Data(v.decode([UInt8].self, forKey: .invitationId)),
      consentID: Data(v.decode([UInt8].self, forKey: .consentId)),
      generation: v.decode(UInt64.self, forKey: .generation),
      consentClass: v.decode(String.self, forKey: .class),
      grant: v.decode(GatewayGrantDTO.self, forKey: .grant).value,
      createdAtMs: v.decode(UInt64.self, forKey: .createdAtMs),
      expiresAtMs: v.decode(UInt64.self, forKey: .expiresAtMs),
      phase: v.decode(GatewayPairingPhase.self, forKey: .phase),
      claimedDeviceKey: v.decodeIfPresent([UInt8].self, forKey: .claimedDeviceKey).map { Data($0) },
      credentialID: v.decodeIfPresent(String.self, forKey: .credentialId),
      receiver: v.decodeIfPresent(Receiver.self, forKey: .receiver)?.value,
      terminal: v.decodeIfPresent(Terminal.self, forKey: .terminal)?.value,
      cleanupPending: v.decode(Bool.self, forKey: .cleanupPending))
  }
  private struct Receiver: Decodable {
    let receiverId: String
    let accessEpoch: UInt64
    var value: GatewayPairingStatus.Receiver { .init(id: receiverId, accessEpoch: accessEpoch) }
  }
  private struct Terminal: Decodable {
    let cause: GatewayPairingTerminalCause
    let initiator: Initiator
    var value: GatewayPairingStatus.Terminal { .init(cause: cause, initiator: initiator.value) }
  }
  private struct Initiator: Decodable {
    let value: GatewayPairingStatus.Initiator
    private enum Keys: String, CodingKey { case kind, principalId, deviceKey }
    init(from decoder: Decoder) throws {
      let v = try decoder.container(keyedBy: Keys.self)
      let kind = try v.decode(GatewayPairingInitiatorKind.self, forKey: .kind)
      let principal = try v.decodeIfPresent(String.self, forKey: .principalId)
      let key = try v.decodeIfPresent([UInt8].self, forKey: .deviceKey)
      switch (kind, principal, key) {
      case (.localOperator, nil, nil): value = .localOperator
      case (.system, nil, nil): value = .system
      case (.principal, .some(let id), nil): value = .principal(id)
      case (.device, nil, .some(let bytes)): value = .device(Data(bytes))
      default: throw NessaGatewayError.invalidFrame
      }
    }
  }
}
struct GatewayPairingCreatedDTO: Decodable {
  let value: GatewayPairingCreated
  private enum Keys: String, CodingKey { case code, status }
  init(from decoder: Decoder) throws {
    try validateGatewayWire(decoder, named: "PairingCreateResult")
    let v = try decoder.container(keyedBy: Keys.self)
    value = try .init(
      code: v.decode(String.self, forKey: .code),
      status: v.decode(GatewayPairingStatusDTO.self, forKey: .status).value)
  }
}
struct GatewayPairingApprovalDTO: Decodable {
  let value: GatewayPairingApproval
  private enum Keys: String, CodingKey { case status, activationStopped }
  init(from decoder: Decoder) throws {
    try validateGatewayWire(decoder, named: "PairingApproveResult")
    let v = try decoder.container(keyedBy: Keys.self)
    value = try .init(
      status: v.decode(GatewayPairingStatusDTO.self, forKey: .status).value,
      activationStopped: v.decodeIfPresent(
        GatewayPairingActivationStop.self, forKey: .activationStopped))
  }
}
struct GatewayPairingPendingDTO: Decodable {
  let values: [GatewayPairingStatus]
  private enum Keys: String, CodingKey { case items }
  init(from decoder: Decoder) throws {
    try validateGatewayWire(decoder, named: "PairingPendingResult")
    let v = try decoder.container(keyedBy: Keys.self)
    values = try v.decode([GatewayPairingStatusDTO].self, forKey: .items).map(\.value)
  }
}

/// Validate the published envelope before Foundation's dictionary Boolean coercion.
struct GatewayPairingEnvelope: Decodable {
  let rejection: GatewayPairingRejection?
  private enum Keys: String, CodingKey { case ok, payload, error }
  private struct Rejection: Decodable {
    let code: String
    let message: String
  }
  init(from decoder: Decoder) throws {
    try validateGatewayWire(decoder, named: "ResFrame")
    let v = try decoder.container(keyedBy: Keys.self)
    if try v.decode(Bool.self, forKey: .ok) {
      guard v.contains(.payload), !v.contains(.error) else { throw NessaGatewayError.invalidFrame }
      rejection = nil
    } else {
      guard v.contains(.error), !v.contains(.payload) else { throw NessaGatewayError.invalidFrame }
      let e = try v.decode(Rejection.self, forKey: .error)
      // Details are captured from the original frame by the response owner.
      rejection = .init(code: e.code, diagnostic: e.message, details: nil)
    }
  }
}
