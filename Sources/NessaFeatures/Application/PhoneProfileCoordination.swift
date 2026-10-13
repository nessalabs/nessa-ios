import Foundation

public struct PhonePairingConfirmation: Equatable, Sendable {
  public let profileID: UUID
  public let invitation: Data
  public let deviceKey: Data
  public init(profileID: UUID, invitation: Data, deviceKey: Data) {
    self.profileID = profileID
    self.invitation = invitation
    self.deviceKey = deviceKey
  }
}

/// Observations remain independent; local enrollment is historical, not current read permission.
public struct PhoneProfileSnapshot: Sendable {
  public let registry: PhoneProfiles
  public let local: RetainedLocalEnrollment?
  public let nativeStatus: RetainedStatus?
  public let nativeRefresh: RetainedRefresh?
  public let source: AuthenticatedGatewaySession?
  public let activationStopped: GatewayPairingActivationStop?
  public init(
    registry: PhoneProfiles, local: RetainedLocalEnrollment?, nativeStatus: RetainedStatus?,
    source: AuthenticatedGatewaySession?, activationStopped: GatewayPairingActivationStop? = nil,
    nativeRefresh: RetainedRefresh? = nil
  ) throws {
    try registry.validate()
    self.registry = registry
    self.local = local
    self.nativeStatus = nativeStatus
    self.nativeRefresh = nativeRefresh
    self.source = source
    self.activationStopped = activationStopped
  }
  public var profile: PhoneProfile { registry.profiles.first { $0.id == registry.selected }! }
  public var confirmation: PhonePairingConfirmation? {
    guard profile.phase != .retired, let owner = profile.pairingStatus, owner.phase == .claimed,
      let local,
      owner.claimedDeviceKey == local.deviceKey
    else { return nil }
    return .init(profileID: profile.id, invitation: owner.invitationID, deviceKey: local.deviceKey)
  }
}

public struct PhoneScopedRetention<Value: Sendable>: Sendable {
  public let profileID: UUID
  public let revision: UUID
  public let value: Value
  public init(profileID: UUID, revision: UUID, value: Value) {
    self.profileID = profileID
    self.revision = revision
    self.value = value
  }
}

public enum PhoneProfileCoordinationRefusal: Error, Equatable, Sendable {
  case busy, closed, noProfile, profileChanged, accountChanged, receiptSourceChanged
  case knownInvitationNeedsRecovery, noInvitation, confirmationChanged, correlationChanged
  case receiverUnavailable, retired
}

/// A failure after admission retains its actual evidence, including an uncertain remote answer.
public struct PhoneProfileCoordinationFailure: Error, Sendable {
  public let operation: UUID
  public let profileID: UUID?
  public let source: AuthenticatedGatewaySession?
  public let owner: GatewayPairingStatus?
  public let nativeStatus: RetainedStatus?
  public let nativeRefresh: RetainedRefresh?
  public let local: RetainedLocalEnrollment?
  public let underlying: any Error
  public init(
    operation: UUID, profileID: UUID?, source: AuthenticatedGatewaySession?,
    owner: GatewayPairingStatus?, nativeStatus: RetainedStatus?, underlying: any Error,
    nativeRefresh: RetainedRefresh? = nil, local: RetainedLocalEnrollment? = nil
  ) {
    self.operation = operation
    self.profileID = profileID
    self.source = source
    self.owner = owner
    self.nativeStatus = nativeStatus
    self.nativeRefresh = nativeRefresh
    self.local = local
    self.underlying = underlying
  }
}

public struct PhoneProfileCloseFailure: Error, Sendable {
  public struct Captured: Sendable {
    public let profileID: UUID
    public let underlying: any Error
    public init(profileID: UUID, underlying: any Error) {
      self.profileID = profileID
      self.underlying = underlying
    }
  }
  public let failures: [Captured]
  public init(failures: [Captured]) { self.failures = failures }
}

public protocol PhoneProfileCoordinating: PhoneScopedRetentionReading {
  func passiveRestore() async throws -> PhoneProfileSnapshot?
  func passiveDisplay(conversations: [String], revision: UUID) async throws -> PhoneRetainedDisplay
  func restore() async throws -> PhoneProfileSnapshot?
  func prepare(_ desired: PhoneProfile, credential: String, on lease: GatewayConnectionLease)
    async throws -> PhoneProfileSnapshot
  func startPairing(on lease: GatewayConnectionLease) async throws -> PhoneProfileSnapshot
  func resolveInvitation(_ invitation: Data, on lease: GatewayConnectionLease) async throws
    -> PhoneProfileSnapshot
  func discardUnenrolled() async throws -> PhoneProfileSnapshot
  func observePairing(on lease: GatewayConnectionLease) async throws -> PhoneProfileSnapshot
  func approve(_ confirmation: PhonePairingConfirmation, on lease: GatewayConnectionLease)
    async throws -> PhoneProfileSnapshot
  func cancelPairing(on lease: GatewayConnectionLease) async throws -> PhoneProfileSnapshot
  func refresh(on lease: GatewayConnectionLease?) async throws -> PhoneProfileSnapshot
  func close() async throws
}

extension PhoneProfileCoordinating {
  public func passiveRestore() async throws -> PhoneProfileSnapshot? {
    throw PhoneProfileCoordinationRefusal.receiverUnavailable
  }
  public func passiveDisplay(conversations: [String], revision: UUID) async throws
    -> PhoneRetainedDisplay
  {
    throw PhoneProfileCoordinationRefusal.receiverUnavailable
  }
}

/// Local purge evidence closes history while retaining the original cleanup payload.
public struct PhonePassivePurgeFailure: Error, Sendable {
  public let profileID: UUID
  public let receipt: RetainedPurge
  public init(profileID: UUID, receipt: RetainedPurge) {
    self.profileID = profileID
    self.receipt = receipt
  }
}
