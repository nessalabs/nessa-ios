import Foundation
import NessaFeatures
import Testing

private enum DeletionProbeFailure: Error { case lost, stale, save }
private actor DeletionStoreProbe: PhoneDeletionIntentStoring {
  var records: [PhoneDeletionRecord] = []
  func loadForDisplay(cache: PhoneCacheScope, profileID: UUID?) -> [PhoneDeletionRecord] {
    records.filter {
      $0.intent.scope.displaySelector == cache.key && $0.intent.scope.profileID == profileID
    }
  }
  var failSave = false
  var failAck = false
  func refuseAcknowledgment() { failAck = true }
  var gate: CoordinatorGate?
  func holdLoad(_ gate: CoordinatorGate) { self.gate = gate }
  func refuseSave() { failSave = true }
  func load(scope: PhoneDeletionScope) async -> [PhoneDeletionRecord] {
    if let gate { await gate.pause() }
    return records.filter { $0.intent.scope == scope }
  }
  func save(_ intent: PhoneDeletionIntent) throws {
    if failSave { throw DeletionProbeFailure.save }
    records.append(.init(intent: intent))
  }
  func acknowledge(_ intent: PhoneDeletionIntent, value: PhoneDeletionAcknowledgment) throws {
    if failAck { throw DeletionProbeFailure.save }
    if let index = records.firstIndex(where: { $0.intent == intent }) {
      records[index] = .init(intent: intent, acknowledgment: value)
    }
  }
}
private actor DeletionProductProbe: GatewayConversationDeleting {
  let source: AuthenticatedGatewaySession
  var calls: [PhoneDeletionIntent] = []
  var checks: [String] = []
  var lost = false
  var wrongRequest = false
  var answerSource: AuthenticatedGatewaySession
  var gate: CoordinatorGate?
  var observation: PhoneDeletionObservation = .readable
  init(_ source: AuthenticatedGatewaySession) {
    self.source = source
    answerSource = source
  }
  func configure(lost: Bool = false, wrongRequest: Bool = false, gate: CoordinatorGate? = nil) {
    self.lost = lost
    self.wrongRequest = wrongRequest
    self.gate = gate
  }
  func changeAnswerSource(_ source: AuthenticatedGatewaySession) { answerSource = source }
  func setObservation(_ value: PhoneDeletionObservation) { observation = value }
  func authenticatedSession(for lease: GatewayConnectionLease) -> AuthenticatedGatewaySession {
    source
  }
  func deleteConversation(_ intent: PhoneDeletionIntent, on lease: GatewayConnectionLease)
    async throws -> PhoneDeletionReceipt<PhoneDeletionAcknowledgment>
  {
    calls.append(intent)
    if let gate { await gate.pause() }
    if lost { throw DeletionProbeFailure.lost }
    return .init(
      source: answerSource,
      value: .init(
        requestId: wrongRequest
          ? UUID().uuidString.lowercased() : intent.requestID.uuidString.lowercased(),
        applied: false))
  }
  func observeDeletion(_ id: String, on lease: GatewayConnectionLease) -> PhoneDeletionReceipt<
    PhoneDeletionObservation
  > {
    checks.append(id)
    return .init(source: answerSource, value: observation)
  }
}
private actor DeletionValidity {
  var valid = true
  func invalidate() { valid = false }
  func check() throws { if !valid { throw DeletionProbeFailure.stale } }
}
private func deletionContext() -> (PhoneDeletionContext, AuthenticatedGatewaySession) {
  let lease = GatewayConnectionLease()
  let scope = PhoneDeletionScope(
    owner: profileIdentity(), productAddress: "ws://127.0.0.1:19743/session", instance: "phone",
    profileID: UUID())
  return (
    .init(scope: scope, lease: lease),
    .init(
      connection: lease,
      snapshot: .init(identity: scope.owner, expiresAt: nil, grants: [], methods: []))
  )
}
@Test func deletionActionDurableSaveRefusalPreventsEffect() async throws {
  let (context, source) = deletionContext()
  let product = DeletionProductProbe(source)
  let store = DeletionStoreProbe()
  await store.refuseSave()
  let action = PhoneConversationDeletion(product: product, store: store)
  do {
    _ = try await action.perform(
      .delete(UUID().uuidString.lowercased()), context: context, current: {})
    Issue.record("Expected save failure")
  } catch let failure as PhoneDeletionFailure {
    #expect(failure.underlying is DeletionProbeFailure)
    #expect(failure.intent != nil)
  }
  #expect(await product.calls.isEmpty)
}
@Test func deletionActionLateFalseAcknowledgmentPersistsOriginalScopeBeforeUIFence() async throws {
  let (context, source) = deletionContext()
  let product = DeletionProductProbe(source)
  let store = DeletionStoreProbe()
  let gate = CoordinatorGate()
  let validity = DeletionValidity()
  await product.configure(gate: gate)
  let action = PhoneConversationDeletion(product: product, store: store)
  let task = Task {
    try await action.perform(
      .delete(UUID().uuidString.lowercased()), context: context,
      current: { try await validity.check() })
  }
  await gate.wait()
  #expect(await store.records.count == 1)
  await validity.invalidate()
  await gate.release()
  do {
    _ = try await task.value
    Issue.record("Expected stale UI refusal")
  } catch let failure as PhoneDeletionFailure {
    #expect(failure.acknowledgment?.applied == false)
    #expect(failure.source == source)
  }
  #expect(await store.records.first?.acknowledgment?.applied == false)
  #expect(try await action.pending(scope: context.scope).first?.acknowledgment?.applied == false)
}
@Test func deletionActionLostReplyBlocksNewRequestAndExplicitRetryIsIdentical() async throws {
  let (context, source) = deletionContext()
  let product = DeletionProductProbe(source)
  let store = DeletionStoreProbe()
  await product.configure(lost: true)
  let action = PhoneConversationDeletion(product: product, store: store)
  let id = UUID().uuidString.lowercased()
  await #expect(throws: PhoneDeletionFailure.self) {
    _ = try await action.perform(.delete(id), context: context, current: {})
  }
  let intent = try #require(await store.records.first?.intent)
  #expect(intent.scope == context.scope)
  await #expect(throws: PhoneDeletionFailure.self) {
    _ = try await action.perform(.delete(id), context: context, current: {})
  }
  #expect(await product.calls == [intent])
  await #expect(throws: PhoneDeletionFailure.self) {
    _ = try await action.perform(.retry(intent), context: context, current: {})
  }
  #expect(await product.calls == [intent, intent])
}
@Test func deletionActionHeldLoadStopsFollowingSaveOrRPC() async throws {
  let (context, source) = deletionContext()
  let product = DeletionProductProbe(source)
  let store = DeletionStoreProbe()
  let gate = CoordinatorGate()
  let validity = DeletionValidity()
  await store.holdLoad(gate)
  let action = PhoneConversationDeletion(product: product, store: store)
  let task = Task {
    try await action.perform(
      .delete(UUID().uuidString.lowercased()), context: context,
      current: { try await validity.check() })
  }
  await gate.wait()
  await validity.invalidate()
  await gate.release()
  await #expect(throws: PhoneDeletionFailure.self) { _ = try await task.value }
  #expect(await store.records.isEmpty)
  #expect(await product.calls.isEmpty)
}
@Test func deletionActionWrongResponseSourceOrRequestNeverAcknowledges() async throws {
  for wrongRequest in [false, true] {
    let (context, source) = deletionContext()
    let product = DeletionProductProbe(source)
    let store = DeletionStoreProbe()
    await product.configure(wrongRequest: wrongRequest)
    if !wrongRequest {
      await product.changeAnswerSource(
        .init(connection: GatewayConnectionLease(), snapshot: source.snapshot))
    }
    let action = PhoneConversationDeletion(product: product, store: store)
    do {
      _ = try await action.perform(
        .delete(UUID().uuidString.lowercased()), context: context, current: {})
      Issue.record("Expected mismatched response")
    } catch let failure as PhoneDeletionFailure {
      #expect(failure.acknowledgment == nil)
      #expect(failure.response?.value.applied == false)
      if wrongRequest {
        #expect(
          failure.response?.value.requestId != failure.intent?.requestID.uuidString.lowercased())
      } else {
        #expect(failure.response?.source != source)
      }
      #expect(failure.underlying is NessaGatewayError)
    }
    #expect(await store.records.first?.acknowledgment == nil)
  }
}
@Test func deletionActionCheckKeepsAbsenceFenceAndReadableDistinctWithoutDispatch() async throws {
  let (context, source) = deletionContext()
  let product = DeletionProductProbe(source)
  let store = DeletionStoreProbe()
  let intent = PhoneDeletionIntent(
    scope: context.scope, requestID: UUID(), conversationID: UUID().uuidString.lowercased())
  try await store.save(intent)
  let action = PhoneConversationDeletion(product: product, store: store)
  for code in ["conversation_not_found", "conversation_deleted", "readable"] {
    let details = Data("{\"retained\":true}".utf8)
    let rejection = GatewayPairingRejection(
      code: code, diagnostic: "owner evidence", details: details)
    await product.setObservation(
      code == "readable"
        ? .readable
        : code == "conversation_deleted" ? .deletionFence(rejection) : .absence(rejection))
    let result = try await action.perform(.check(intent), context: context, current: {})
    #expect(result.acknowledgment == nil)
    switch result.observation {
    case .absence(let evidence):
      #expect(code == "conversation_not_found")
      #expect(evidence.details == details)
    case .deletionFence(let evidence):
      #expect(code == "conversation_deleted")
      #expect(evidence.diagnostic == "owner evidence")
    case .readable: #expect(code == "readable")
    default: Issue.record("Missing observation")
    }
  }
  #expect(await product.calls.isEmpty)
  #expect(try await action.pending(scope: context.scope).count == 1)
}
@Test func deletionActionAckPublicationFailureRetainsReceivedEvidence() async throws {
  let (context, source) = deletionContext()
  let product = DeletionProductProbe(source)
  let store = DeletionStoreProbe()
  await store.refuseAcknowledgment()
  let action = PhoneConversationDeletion(product: product, store: store)
  do {
    _ = try await action.perform(
      .delete(UUID().uuidString.lowercased()), context: context, current: {})
    Issue.record("Expected ack durability failure")
  } catch let failure as PhoneDeletionFailure {
    #expect(failure.acknowledgment?.applied == false)
    #expect(failure.intent != nil)
    #expect(failure.source == source)
    #expect(failure.underlying is DeletionProbeFailure)
  }
  #expect(await store.records.first?.acknowledgment == nil)
}
@Test func deletionActionRetryCannotRetargetOwnerInstanceOrConversation() async throws {
  for field in ["owner", "instance", "target"] {
    let (context, source) = deletionContext()
    let product = DeletionProductProbe(source)
    let store = DeletionStoreProbe()
    let original = PhoneDeletionIntent(
      scope: context.scope, requestID: UUID(), conversationID: UUID().uuidString.lowercased())
    try await store.save(original)
    let scope = PhoneDeletionScope(
      owner: field == "owner"
        ? profileIdentity(["owner", "owner", "owner", "owner", "new-owner-credential", "owner"])
        : original.scope.owner,
      productAddress: original.scope.productAddress,
      instance: field == "instance" ? "another-phone" : original.scope.instance,
      profileID: original.scope.profileID)
    let changed = PhoneDeletionIntent(
      scope: scope, requestID: original.requestID,
      conversationID: field == "target" ? UUID().uuidString.lowercased() : original.conversationID)
    let action = PhoneConversationDeletion(product: product, store: store)
    do {
      _ = try await action.perform(.retry(changed), context: context, current: {})
      Issue.record("Expected immutable target refusal")
    } catch let failure as PhoneDeletionFailure { #expect(failure.intent == changed) }
    #expect(await product.calls.isEmpty)
    #expect(await product.checks.isEmpty)
  }
}
@Test func deletionActionDisplayRoutingCannotAuthenticateAnotherOwnerRetry() async throws {
  let (originalContext, _) = deletionContext()
  let cache = PhoneCacheScope(
    address: originalContext.scope.productAddress, credential: "same-local-cache-token",
    instance: originalContext.scope.instance)
  let original = PhoneDeletionScope(
    owner: originalContext.scope.owner, productAddress: originalContext.scope.productAddress,
    instance: originalContext.scope.instance, profileID: originalContext.scope.profileID,
    displayCache: cache)
  let replacement = PhoneDeletionScope(
    owner: profileIdentity(["owner", "owner", "owner", "owner", "replacement-owner", "owner"]),
    productAddress: original.productAddress, instance: original.instance,
    profileID: original.profileID, displayCache: cache)
  let root = profileTestRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = PhoneDeletionIntentStore(root: root)
  let intent = PhoneDeletionIntent(
    scope: original, requestID: UUID(), conversationID: UUID().uuidString.lowercased())
  try await store.save(intent)
  let lease = GatewayConnectionLease()
  let source = AuthenticatedGatewaySession(
    connection: lease,
    snapshot: .init(identity: replacement.owner, expiresAt: nil, grants: [], methods: []))
  let product = DeletionProductProbe(source)
  let action = PhoneConversationDeletion(
    product: product, store: PhoneDeletionIntentStore(root: root))
  #expect(
    try await action.pendingForDisplay(cache: cache, profileID: original.profileID).map(\.intent)
      == [intent])
  #expect(await product.calls.isEmpty)
  await #expect(throws: PhoneDeletionFailure.self) {
    _ = try await action.perform(
      .retry(intent), context: .init(scope: replacement, lease: lease), current: {})
  }
  #expect(await product.calls.isEmpty)
  #expect(await product.checks.isEmpty)
}
