import Foundation

/// Owner control-plane evidence. Even an active invitation is not authority to read.
public struct GatewayPairingStatus: Codable, Equatable, Sendable {
  public enum Initiator: Codable, Equatable, Sendable {
    case localOperator
    case principal(String)
    case device(Data)
    case system
    public static func == (lhs: Self, rhs: Self) -> Bool {
      switch (lhs, rhs) {
      case (.localOperator, .localOperator), (.system, .system): return true
      case (.principal(let a), .principal(let b)): return a.utf8.elementsEqual(b.utf8)
      case (.device(let a), .device(let b)): return a == b
      default: return false
      }
    }
  }
  public struct Terminal: Codable, Equatable, Sendable {
    public let cause: GatewayPairingTerminalCause
    public let initiator: Initiator
    public init(cause: GatewayPairingTerminalCause, initiator: Initiator) {
      self.cause = cause
      self.initiator = initiator
    }
  }
  public struct Receiver: Codable, Equatable, Sendable {
    public let id: String
    public let accessEpoch: UInt64
    public init(id: String, accessEpoch: UInt64) {
      self.id = id
      self.accessEpoch = accessEpoch
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
      lhs.id.utf8.elementsEqual(rhs.id.utf8) && lhs.accessEpoch == rhs.accessEpoch
    }
  }
  public let invitationID: Data
  public let consentID: Data
  public let generation: UInt64
  public let consentClass: String
  public let grant: GatewaySessionSnapshot.Grant
  public let createdAtMs: UInt64
  public let expiresAtMs: UInt64
  public let phase: GatewayPairingPhase
  public let claimedDeviceKey: Data?
  public let credentialID: String?
  public let receiver: Receiver?
  public let terminal: Terminal?
  public let cleanupPending: Bool
  public init(
    invitationID: Data, consentID: Data, generation: UInt64, consentClass: String,
    grant: GatewaySessionSnapshot.Grant, createdAtMs: UInt64, expiresAtMs: UInt64,
    phase: GatewayPairingPhase, claimedDeviceKey: Data?, credentialID: String?,
    receiver: Receiver?, terminal: Terminal?, cleanupPending: Bool
  ) {
    self.invitationID = invitationID
    self.consentID = consentID
    self.generation = generation
    self.consentClass = consentClass
    self.grant = grant
    self.createdAtMs = createdAtMs
    self.expiresAtMs = expiresAtMs
    self.phase = phase
    self.claimedDeviceKey = claimedDeviceKey
    self.credentialID = credentialID
    self.receiver = receiver
    self.terminal = terminal
    self.cleanupPending = cleanupPending
  }
  public static func == (lhs: Self, rhs: Self) -> Bool {
    let credentialEqual: Bool
    switch (lhs.credentialID, rhs.credentialID) {
    case (nil, nil): credentialEqual = true
    case (.some(let a), .some(let b)): credentialEqual = a.utf8.elementsEqual(b.utf8)
    default: credentialEqual = false
    }
    return lhs.invitationID == rhs.invitationID && lhs.consentID == rhs.consentID
      && lhs.generation == rhs.generation
      && lhs.consentClass.utf8.elementsEqual(rhs.consentClass.utf8)
      && lhs.grant == rhs.grant && lhs.createdAtMs == rhs.createdAtMs
      && lhs.expiresAtMs == rhs.expiresAtMs
      && lhs.phase == rhs.phase && lhs.claimedDeviceKey == rhs.claimedDeviceKey && credentialEqual
      && lhs.receiver == rhs.receiver && lhs.terminal == rhs.terminal
      && lhs.cleanupPending == rhs.cleanupPending
  }
}

/// The code is ephemeral: deliberately no Codable conformance or saved-profile field.
public struct GatewayPairingCreated: Sendable {
  public let code: String
  public let status: GatewayPairingStatus
  public init(code: String, status: GatewayPairingStatus) {
    self.code = code
    self.status = status
  }
}
public struct GatewayPairingApproval: Equatable, Sendable {
  public let status: GatewayPairingStatus
  public let activationStopped: GatewayPairingActivationStop?
  public init(status: GatewayPairingStatus, activationStopped: GatewayPairingActivationStop?) {
    self.status = status
    self.activationStopped = activationStopped
  }
}
public struct GatewayPairingReceipt<Value: Sendable>: Sendable {
  public let source: AuthenticatedGatewaySession
  public let value: Value
  public init(source: AuthenticatedGatewaySession, value: Value) {
    self.source = source
    self.value = value
  }
}

/// Only wire codes select behavior. The diagnostic and optional JSON details remain evidence.
public struct GatewayPairingRejection: Error, Sendable {
  public enum Kind: Sendable {
    case known(GatewayPairingKnownError)
    case forbidden, invalidRequest, unknownMethod
    case unknown(String)
  }
  public let code: String
  public let diagnostic: String
  public let details: Data?
  public var kind: Kind {
    if let known = GatewayPairingKnownError(rawValue: code) { return .known(known) }
    switch code {
    case "forbidden": return .forbidden
    case "invalid_request": return .invalidRequest
    case "unknown_method": return .unknownMethod
    default: return .unknown(code)
    }
  }
  public init(code: String, diagnostic: String, details: Data?) {
    self.code = code
    self.diagnostic = diagnostic
    self.details = details
  }
}
/// Thrown only after pending admission. A transport failure leaves the remote outcome unknown.
public struct GatewayPairingOperationFailure: Error, Sendable {
  public let source: AuthenticatedGatewaySession
  public let underlying: any Error
  public init(source: AuthenticatedGatewaySession, underlying: any Error) {
    self.source = source
    self.underlying = underlying
  }
}
public protocol GatewayPairingManaging: Sendable {
  func createDevice(on lease: GatewayConnectionLease) async throws -> GatewayPairingReceipt<
    GatewayPairingCreated
  >
  func pairingStatus(_ invitation: Data, on lease: GatewayConnectionLease) async throws
    -> GatewayPairingReceipt<GatewayPairingStatus>
  func approvePairing(_ invitation: Data, deviceKey: Data, on lease: GatewayConnectionLease)
    async throws -> GatewayPairingReceipt<GatewayPairingApproval>
  func cancelPairing(_ invitation: Data, on lease: GatewayConnectionLease) async throws
    -> GatewayPairingReceipt<GatewayPairingStatus>
  func pendingPairings(on lease: GatewayConnectionLease) async throws -> GatewayPairingReceipt<
    [GatewayPairingStatus]
  >
}
