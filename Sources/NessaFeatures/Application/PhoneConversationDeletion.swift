import Foundation

public struct PhoneDeletionScope: Codable, Sendable, Equatable {
  public let owner: GatewaySessionSnapshot.Identity
  public let productAddress: String
  public let instance: String
  public let profileID: UUID?
  public let displaySelector: String?
  public init(
    owner: GatewaySessionSnapshot.Identity, productAddress: String, instance: String,
    profileID: UUID? = nil, displayCache: PhoneCacheScope? = nil
  ) {
    self.owner = owner
    self.productAddress = productAddress
    self.instance = instance
    self.profileID = profileID
    self.displaySelector = displayCache?.key
  }
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.owner == rhs.owner && lhs.profileID == rhs.profileID
      && lhs.displaySelector == rhs.displaySelector
      && lhs.productAddress.utf8.elementsEqual(rhs.productAddress.utf8)
      && lhs.instance.utf8.elementsEqual(rhs.instance.utf8)
  }
}
public struct PhoneDeletionIntent: Codable, Sendable, Equatable {
  public let scope: PhoneDeletionScope
  public let requestID: UUID
  public let conversationID: String
  public init(scope: PhoneDeletionScope, requestID: UUID, conversationID: String) {
    self.scope = scope
    self.requestID = requestID
    self.conversationID = conversationID
  }
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.scope == rhs.scope && lhs.requestID == rhs.requestID
      && lhs.conversationID.utf8.elementsEqual(rhs.conversationID.utf8)
  }
}
public struct PhoneDeletionAcknowledgment: Codable, Sendable, Equatable {
  public let requestId: String
  public let applied: Bool
  public init(requestId: String, applied: Bool) {
    self.requestId = requestId
    self.applied = applied
  }
}
public struct PhoneDeletionRecord: Codable, Sendable, Equatable {
  public let intent: PhoneDeletionIntent
  public let acknowledgment: PhoneDeletionAcknowledgment?
  public init(intent: PhoneDeletionIntent, acknowledgment: PhoneDeletionAcknowledgment? = nil) {
    self.intent = intent
    self.acknowledgment = acknowledgment
  }
}
public struct PhoneDeletionContext: Sendable {
  public let scope: PhoneDeletionScope
  public let lease: GatewayConnectionLease
  public init(scope: PhoneDeletionScope, lease: GatewayConnectionLease) {
    self.scope = scope
    self.lease = lease
  }
}
public enum PhoneDeletionObservation: Sendable {
  case readable
  case deletionFence(GatewayPairingRejection)
  case absence(GatewayPairingRejection)
}
public struct PhoneDeletionReceipt<Value: Sendable>: Sendable {
  public let source: AuthenticatedGatewaySession
  public let value: Value
  public init(source: AuthenticatedGatewaySession, value: Value) {
    self.source = source
    self.value = value
  }
}
public protocol GatewayConversationDeleting: AuthenticatedGatewaySessionProviding {
  func deleteConversation(_ intent: PhoneDeletionIntent, on lease: GatewayConnectionLease)
    async throws
    -> PhoneDeletionReceipt<PhoneDeletionAcknowledgment>
  func observeDeletion(_ id: String, on lease: GatewayConnectionLease) async throws
    -> PhoneDeletionReceipt<PhoneDeletionObservation>
}
public protocol PhoneDeletionIntentStoring: Sendable {
  func loadForDisplay(cache: PhoneCacheScope, profileID: UUID?) async throws
    -> [PhoneDeletionRecord]
  func load(scope: PhoneDeletionScope) async throws -> [PhoneDeletionRecord]
  func save(_ intent: PhoneDeletionIntent) async throws
  func acknowledge(_ intent: PhoneDeletionIntent, value: PhoneDeletionAcknowledgment) async throws
}
public enum PhoneDeletionOperation: Sendable {
  case delete(String)
  case check(PhoneDeletionIntent)
  case retry(PhoneDeletionIntent)
}
public enum PhoneDeletionRefusal: Error, Sendable { case busy, changed, unresolved }
public struct PhoneDeletionResult: Sendable {
  public let source: AuthenticatedGatewaySession
  public let intent: PhoneDeletionIntent
  public let acknowledgment: PhoneDeletionAcknowledgment?
  public let observation: PhoneDeletionObservation?
}
public struct PhoneDeletionFailure: Error, Sendable {
  public let response: PhoneDeletionReceipt<PhoneDeletionAcknowledgment>?
  public let source: AuthenticatedGatewaySession?
  public let intent: PhoneDeletionIntent?
  public let acknowledgment: PhoneDeletionAcknowledgment?
  public let underlying: any Error
}
/// Durable deletion identity is separate from execution receipts and retained tombstones.
public actor PhoneConversationDeletion {
  private let product: any GatewayConversationDeleting
  private let store: any PhoneDeletionIntentStoring
  private let makeID: @Sendable () -> UUID
  private var admitted = false
  public init(
    product: any GatewayConversationDeleting, store: any PhoneDeletionIntentStoring,
    makeID: @escaping @Sendable () -> UUID = { UUID() }
  ) {
    self.product = product
    self.store = store
    self.makeID = makeID
  }
  public func pending(scope: PhoneDeletionScope) async throws -> [PhoneDeletionRecord] {
    try await store.load(scope: scope)
  }
  public func pendingForDisplay(cache: PhoneCacheScope, profileID: UUID? = nil) async throws
    -> [PhoneDeletionRecord]
  {
    try await store.loadForDisplay(cache: cache, profileID: profileID)
  }
  public func perform(
    _ operation: PhoneDeletionOperation, context: PhoneDeletionContext,
    current: @Sendable () async throws -> Void
  ) async throws -> PhoneDeletionResult {
    guard !admitted else { throw PhoneDeletionRefusal.busy }
    try Task.checkCancellation()
    admitted = true
    defer { admitted = false }
    var source: AuthenticatedGatewaySession?
    var intent: PhoneDeletionIntent?
    var acknowledgment: PhoneDeletionAcknowledgment?
    var response: PhoneDeletionReceipt<PhoneDeletionAcknowledgment>?
    switch operation {
    case .check(let saved), .retry(let saved): intent = saved
    default: break
    }
    do {
      try await current()
      let captured = try await product.authenticatedSession(for: context.lease)
      source = captured
      try await current()
      guard captured.connection == context.lease, captured.snapshot.identity == context.scope.owner
      else { throw PhoneDeletionRefusal.changed }
      let records = try await store.load(scope: context.scope)
      try await current()
      switch operation {
      case .delete(let id):
        guard
          !records.contains(where: {
            $0.acknowledgment == nil && $0.intent.conversationID.utf8.elementsEqual(id.utf8)
          })
        else { throw PhoneDeletionRefusal.unresolved }
        intent = .init(scope: context.scope, requestID: makeID(), conversationID: id)
        try await store.save(intent!)
        try await current()
      case .check(let saved), .retry(let saved):
        guard saved.scope == context.scope, records.contains(where: { $0.intent == saved })
        else { throw PhoneDeletionRefusal.changed }
      }
      if case .check = operation {
        let observed = try await product.observeDeletion(intent!.conversationID, on: context.lease)
        try await current()
        guard observed.source == captured else { throw PhoneDeletionRefusal.changed }
        return .init(
          source: captured, intent: intent!, acknowledgment: nil, observation: observed.value)
      }
      let answer = try await product.deleteConversation(intent!, on: context.lease)
      response = answer
      guard answer.source == captured,
        answer.value.requestId.utf8.elementsEqual(intent!.requestID.uuidString.lowercased().utf8)
      else { throw NessaGatewayError.invalidFrame }
      acknowledgment = answer.value
      // This accepted historical receipt belongs to its original store even after UI invalidation.
      try await store.acknowledge(intent!, value: answer.value)
      try await current()
      return .init(
        source: captured, intent: intent!, acknowledgment: answer.value, observation: nil)
    } catch {
      throw PhoneDeletionFailure(
        response: response, source: source, intent: intent, acknowledgment: acknowledgment,
        underlying: error)
    }
  }
}
