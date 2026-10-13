import Foundation

public enum PhoneSetupOperation: Sendable {
  case prepare(nativeAddress: String, newProfile: Bool)
  case pair, observe, restore, cancel, discard, findInvitations
  case approve(PhonePairingConfirmation)
  case recover(Data)
  public var requiresProductConnection: Bool {
    switch self {
    case .restore, .discard: false
    default: true
    }
  }
}
public enum PhoneSetupRefusal: Error, Equatable, Sendable {
  case busy, notConnected, unavailable, changed, changedSetup, noProfile
}
/// Ephemeral material from the current product owner; never serialized or published.
public struct PhoneSetupContext: Sendable {
  public let connection: PhoneProductConnection?
  public let lease: GatewayConnectionLease?
  public let snapshot: PhoneProfileSnapshot?
  public init(
    connection: PhoneProductConnection?, lease: GatewayConnectionLease?,
    snapshot: PhoneProfileSnapshot?
  ) {
    self.connection = connection
    self.lease = lease
    self.snapshot = snapshot
  }
  public func productLease() throws -> GatewayConnectionLease {
    guard let lease else { throw PhoneSetupRefusal.notConnected }
    return lease
  }
}
public struct PhoneSetupResult: Sendable {
  public let snapshot: PhoneProfileSnapshot?
  public let invitations: [GatewayPairingStatus]?
  public init(snapshot: PhoneProfileSnapshot?, invitations: [GatewayPairingStatus]? = nil) {
    self.snapshot = snapshot
    self.invitations = invitations
  }
}
public struct PhoneSetupFailure: Error, Sendable {
  public let snapshot: PhoneProfileSnapshot?
  public let source: AuthenticatedGatewaySession?
  public let underlying: any Error
  public init(
    snapshot: PhoneProfileSnapshot?, source: AuthenticatedGatewaySession?,
    underlying: any Error
  ) {
    self.snapshot = snapshot
    self.source = source
    self.underlying = underlying
  }
}

/// Explicit setup choices use the same leased product and native owners as normal chat.
public struct PhoneSetupActions: Sendable {
  private let service: MessagingService
  private let sync: any PhoneSyncRunning
  private let makeID: @Sendable () -> UUID
  public init(
    service: MessagingService, sync: any PhoneSyncRunning,
    makeID: @escaping @Sendable () -> UUID = { UUID() }
  ) {
    self.service = service
    self.sync = sync
    self.makeID = makeID
  }
  public func perform(
    _ operation: PhoneSetupOperation, context: PhoneSetupContext,
    current: @Sendable () async throws -> Void
  ) async throws -> PhoneSetupResult {
    var observed = context.snapshot
    var source: AuthenticatedGatewaySession?
    do {
      try await current()
      switch operation {
      case .prepare(let nativeAddress, let newProfile):
        let lease = try context.productLease()
        guard let connection = context.connection, !connection.credential.isEmpty else {
          throw PhoneSetupRefusal.notConnected
        }
        source = try await service.authenticatedSession(for: lease)
        try await current()
        guard source?.connection == context.lease, let source else {
          throw PhoneSetupRefusal.changed
        }
        let desired: PhoneProfile
        if newProfile || context.snapshot == nil {
          desired = .init(
            id: makeID(), productAddress: connection.address,
            instance: connection.instance, nativeAddress: nativeAddress,
            identity: source.snapshot.identity)
        } else {
          guard let original = context.snapshot?.profile,
            original.nativeAddress.utf8.elementsEqual(nativeAddress.utf8)
          else { throw PhoneSetupRefusal.changedSetup }
          desired = original
        }
        observed = try await sync.prepare(
          desired, credential: connection.credential,
          on: try context.productLease())
      case .pair:
        observed = try await sync.startPairing(on: try context.productLease())
        try await current()
        observed = try await sync.observePairing(on: try context.productLease())
      case .observe:
        observed = try await sync.observePairing(on: try context.productLease())
      case .restore:
        observed = try await sync.restore()
      case .approve(let confirmation):
        guard context.snapshot?.confirmation == confirmation else {
          throw PhoneSetupRefusal.changed
        }
        observed = try await sync.approve(confirmation, on: try context.productLease())
      case .cancel:
        observed = try await sync.cancelPairing(on: try context.productLease())
      case .discard:
        observed = try await sync.discardUnenrolled()
      case .recover(let invitation):
        observed = try await sync.resolveInvitation(invitation, on: try context.productLease())
      case .findInvitations:
        source = try await service.authenticatedSession(for: try context.productLease())
        try await current()
        guard let source, source.connection == context.lease,
          context.snapshot?.profile.identity == source.snapshot.identity
        else { throw PhoneSetupRefusal.changed }
        let pending = try await service.pendingPairings(on: try context.productLease())
        try await current()
        guard pending.source == source else { throw PhoneSetupRefusal.changed }
        return .init(snapshot: observed, invitations: pending.value)
      }
      try await current()
      return .init(snapshot: observed)
    } catch {
      throw PhoneSetupFailure(snapshot: observed, source: source, underlying: error)
    }
  }
}
