import Foundation

public struct PhoneConversationShare: Codable, Sendable, Equatable {
  public let credentialId: String
  /// What the grant allows: read; read and comment; or read, comment and drive.
  public let capabilities: [String]
  public let policy: PhoneConversationToolPolicy?
  public let policyRevision: UInt64
  public let grantedAtMs: UInt64
  public init(
    credentialId: String, capabilities: [String], policy: PhoneConversationToolPolicy? = nil,
    policyRevision: UInt64, grantedAtMs: UInt64
  ) {
    self.credentialId = credentialId
    self.capabilities = capabilities
    self.policy = policy
    self.policyRevision = policyRevision
    self.grantedAtMs = grantedAtMs
  }
}
public struct PhoneConversationToolPolicy: Codable, Sendable, Equatable {
  public let preset: String?
  public let allow: [String]?
  public let deny: [String]?
  public init(preset: String? = nil, allow: [String]? = nil, deny: [String]? = nil) {
    self.preset = preset
    self.allow = allow
    self.deny = deny
  }
}
public struct PhoneConversationShareAcknowledgment: Codable, Sendable, Equatable {
  public let requestId: String
  public let applied: Bool
  public init(requestId: String, applied: Bool) {
    self.requestId = requestId
    self.applied = applied
  }
}
public struct PhoneConversationShareIntent: Codable, Sendable, Equatable {
  public let requestID: UUID
  public let conversationID: String
  public let profileID: UUID
  public let owner: GatewaySessionSnapshot.Identity
  public let instance: String
  public let device: GatewayPairingStatus
  public init(
    requestID: UUID, conversationID: String, profileID: UUID,
    owner: GatewaySessionSnapshot.Identity, instance: String, device: GatewayPairingStatus
  ) {
    self.requestID = requestID
    self.conversationID = conversationID
    self.profileID = profileID
    self.owner = owner
    self.instance = instance
    self.device = device
  }
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.requestID == rhs.requestID && lhs.profileID == rhs.profileID
      && lhs.conversationID.utf8.elementsEqual(rhs.conversationID.utf8)
      && lhs.instance.utf8.elementsEqual(rhs.instance.utf8)
      && lhs.owner == rhs.owner && lhs.device == rhs.device
  }
}
public struct PhoneConversationShareReceipt<Value: Sendable>: Sendable {
  public let source: AuthenticatedGatewaySession
  public let value: Value
  public init(source: AuthenticatedGatewaySession, value: Value) {
    self.source = source
    self.value = value
  }
}
public protocol GatewayConversationSharingProviding: AuthenticatedGatewaySessionProviding {
  func ownerConversationChoices(on lease: GatewayConnectionLease) async throws
    -> PhoneConversationShareReceipt<NessaConversationList>
  func conversationShares(_ id: String, on lease: GatewayConnectionLease) async throws
    -> PhoneConversationShareReceipt<[PhoneConversationShare]>
  func setConversationRead(_ intent: PhoneConversationShareIntent, on lease: GatewayConnectionLease)
    async throws -> PhoneConversationShareReceipt<PhoneConversationShareAcknowledgment>
}
public struct PhoneConversationShareRecord: Codable, Sendable, Equatable {
  public let intent: PhoneConversationShareIntent
  public let acknowledgment: PhoneConversationShareAcknowledgment?
  public init(
    intent: PhoneConversationShareIntent,
    acknowledgment: PhoneConversationShareAcknowledgment? = nil
  ) {
    self.intent = intent
    self.acknowledgment = acknowledgment
  }
}
public protocol PhoneConversationShareIntentStoring: Sendable {
  func load(profileID: UUID) async throws -> [PhoneConversationShareRecord]
  func acknowledge(
    _ intent: PhoneConversationShareIntent, value: PhoneConversationShareAcknowledgment)
    async throws
  func save(_ intent: PhoneConversationShareIntent) async throws
}
public enum PhoneConversationSharingOperation: Sendable {
  case choices
  case share(String)
  case check(PhoneConversationShareIntent)
  case retry(PhoneConversationShareIntent)
}
public enum PhoneConversationSharingRefusal: Error, Sendable { case busy, changed, noDevice }
public struct PhoneConversationSharingResult: Sendable {
  public let snapshot: PhoneProfileSnapshot
  public let source: AuthenticatedGatewaySession
  public let choices: NessaConversationList?
  public let shares: [PhoneConversationShare]?
  public let intent: PhoneConversationShareIntent?
  public let acknowledgment: PhoneConversationShareAcknowledgment?
}
public struct PhoneConversationSharingFailure: Error, Sendable {
  public let source: AuthenticatedGatewaySession?
  public let snapshot: PhoneProfileSnapshot?
  public let intent: PhoneConversationShareIntent?
  public let acknowledgment: PhoneConversationShareAcknowledgment?
  public let underlying: any Error
}

/// Shares use owner decisions and current grants; these results never assert native readiness.
public actor PhoneConversationSharing {
  private let product: any GatewayConversationSharingProviding
  private let sync: any PhoneSyncRunning
  private let store: any PhoneConversationShareIntentStoring
  private let makeID: @Sendable () -> UUID
  private var admitted = false
  public init(
    product: any GatewayConversationSharingProviding, sync: any PhoneSyncRunning,
    store: any PhoneConversationShareIntentStoring,
    makeID: @escaping @Sendable () -> UUID = { UUID() }
  ) {
    self.product = product
    self.sync = sync
    self.store = store
    self.makeID = makeID
  }
  public func pending(profileID: UUID) async throws -> [PhoneConversationShareIntent] {
    try await store.load(profileID: profileID).filter { $0.acknowledgment == nil }.map(\.intent)
  }
  public func perform(
    _ operation: PhoneConversationSharingOperation, context: PhoneSetupContext,
    current: @Sendable () async throws -> Void
  ) async throws -> PhoneConversationSharingResult {
    guard !admitted else { throw PhoneConversationSharingRefusal.busy }
    try Task.checkCancellation()
    admitted = true
    defer { admitted = false }
    var snapshot = context.snapshot
    var capturedSource: AuthenticatedGatewaySession?
    var intent: PhoneConversationShareIntent?
    switch operation {
    case .check(let saved), .retry(let saved): intent = saved
    default: break
    }
    var acknowledgment: PhoneConversationShareAcknowledgment?
    do {
      try await current()
      let lease = try context.productLease()
      let source = try await product.authenticatedSession(for: lease)
      capturedSource = source
      try await current()
      guard let original = context.snapshot, source.connection == lease,
        source.snapshot.identity == original.profile.identity
      else { throw PhoneConversationSharingRefusal.changed }
      let observed = try await sync.observePairing(on: lease)
      snapshot = observed
      try await current()
      guard observed.source == source, observed.profile.sameSetup(as: original.profile),
        let device = observed.profile.pairingStatus, device.phase == .active,
        let local = observed.local, let issued = local.issued,
        let credential = device.credentialID, let receiver = device.receiver,
        PhonePairingCorrelation.equal(credential, issued.credential),
        PhonePairingCorrelation.equal(receiver.id, issued.receiver),
        PhonePairingCorrelation.equal(receiver.id, observed.profile.nativeReceiver ?? "")
      else { throw PhoneConversationSharingRefusal.noDevice }
      try PhonePairingCorrelation.validate(device, local: local, profile: observed.profile)
      func checkedSource<Value>(_ receipt: PhoneConversationShareReceipt<Value>) throws {
        guard receipt.source == source else { throw PhoneConversationSharingRefusal.changed }
      }
      if case .choices = operation {
        let choices = try await product.ownerConversationChoices(on: lease)
        try await current()
        try checkedSource(choices)
        return .init(
          snapshot: observed, source: source, choices: choices.value, shares: nil,
          intent: nil, acknowledgment: nil)
      }
      let id: String
      switch operation {
      case .share(let selected): id = selected
      case .check(let saved), .retry(let saved):
        intent = saved
        id = saved.conversationID
        let stored = try await store.load(profileID: saved.profileID)
        try await current()
        guard saved.profileID == observed.profile.id, saved.owner == source.snapshot.identity,
          PhonePairingCorrelation.equal(saved.instance, observed.profile.instance),
          saved.device == device,
          stored.contains(where: { $0.intent == saved })
        else { throw PhoneConversationSharingRefusal.changed }
      case .choices: throw PhoneConversationSharingRefusal.changed
      }
      var grants = try await product.conversationShares(id, on: lease)
      try await current()
      try checkedSource(grants)
      let exists = grants.value.contains {
        PhonePairingCorrelation.equal($0.credentialId, credential)
      }
      let dispatch: Bool
      switch operation {
      case .share: dispatch = !exists
      case .retry: dispatch = true
      default: dispatch = false
      }
      if dispatch {
        if intent == nil {
          // Do not substitute a new request for an unresolved selection, even across restart.
          let pending = try await store.load(profileID: observed.profile.id)
          try await current()
          guard
            !pending.contains(where: {
              $0.acknowledgment == nil
                && PhonePairingCorrelation.equal($0.intent.conversationID, id)
                && $0.intent.owner == source.snapshot.identity
            })
          else { throw PhoneConversationSharingRefusal.changed }
          intent = .init(
            requestID: makeID(), conversationID: id, profileID: observed.profile.id,
            owner: source.snapshot.identity, instance: observed.profile.instance, device: device)
          try await store.save(intent!)
        }
        try await current()
        let answer = try await product.setConversationRead(intent!, on: lease)
        acknowledgment = answer.value
        try await current()
        try checkedSource(answer)
        guard
          answer.value.requestId.utf8.elementsEqual(intent!.requestID.uuidString.lowercased().utf8)
        else { throw NessaGatewayError.invalidFrame }
        try await store.acknowledge(intent!, value: answer.value)
        try await current()
        grants = try await product.conversationShares(id, on: lease)
        try await current()
        try checkedSource(grants)
      }
      return .init(
        snapshot: observed, source: source, choices: nil, shares: grants.value,
        intent: intent, acknowledgment: acknowledgment)
    } catch {
      throw PhoneConversationSharingFailure(
        source: capturedSource, snapshot: snapshot, intent: intent,
        acknowledgment: acknowledgment, underlying: error)
    }
  }
}
