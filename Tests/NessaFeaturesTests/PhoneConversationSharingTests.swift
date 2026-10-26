import Foundation
import NessaFeatures
import Testing

private enum SharingProbeFailure: Error { case stale, observe, lost }
private actor SharingSyncProbe: PhoneSyncRunning {
  let snapshot: PhoneProfileSnapshot
  var calls: [String] = []
  var prepared: PhoneProfile?
  var credential: String?
  var leases: [GatewayConnectionLease] = []
  var recovered: Data?
  var confirmation: PhonePairingConfirmation?
  var pairGate: CoordinatorGate?
  var failObserve = false
  init(_ snapshot: PhoneProfileSnapshot) { self.snapshot = snapshot }
  func holdPair(_ gate: CoordinatorGate) { pairGate = gate }
  func failingObserve() { failObserve = true }
  func startup() -> PhoneSyncStartup? { nil }
  func savedProfiles() -> PhoneProfiles? { snapshot.registry }
  func restore() -> PhoneProfileSnapshot? {
    calls.append("restore")
    return snapshot
  }
  func prepare(_ desired: PhoneProfile, credential: String, on lease: GatewayConnectionLease) throws
    -> PhoneProfileSnapshot
  {
    calls.append("prepare")
    prepared = desired
    self.credential = credential
    leases.append(lease)
    return try .init(
      registry: exampleProfiles(desired.changingPhase(to: .prepared)), local: nil,
      nativeStatus: nil, source: nil)
  }
  func startPairing(on lease: GatewayConnectionLease) async -> PhoneProfileSnapshot {
    calls.append("pair")
    leases.append(lease)
    if let pairGate { await pairGate.pause() }
    return snapshot
  }
  func observePairing(on lease: GatewayConnectionLease) throws -> PhoneProfileSnapshot {
    calls.append("observe")
    leases.append(lease)
    if failObserve { throw SharingProbeFailure.observe }
    return snapshot
  }
  func approve(_ confirmation: PhonePairingConfirmation, on lease: GatewayConnectionLease)
    -> PhoneProfileSnapshot
  {
    calls.append("approve")
    self.confirmation = confirmation
    leases.append(lease)
    return snapshot
  }
  func resolveInvitation(_ invitation: Data, on lease: GatewayConnectionLease)
    -> PhoneProfileSnapshot
  {
    calls.append("recover")
    recovered = invitation
    leases.append(lease)
    return snapshot
  }
  func cancelPairing(on lease: GatewayConnectionLease) -> PhoneProfileSnapshot {
    calls.append("cancel")
    leases.append(lease)
    return snapshot
  }
  func discardUnenrolled() -> PhoneProfileSnapshot {
    calls.append("discard")
    return snapshot
  }
  func refresh(on lease: GatewayConnectionLease?) throws -> PhoneProfileSnapshot {
    throw SharingProbeFailure.stale
  }
  func cataloguePage(after: RetainedEntryKey?, maximum: UInt32) throws -> PhoneScopedRetention<
    RetainedCataloguePage?
  > { throw SharingProbeFailure.stale }
  func transcript(conversation: String, revision: UUID) throws -> PhoneScopedRetention<
    RetainedTranscript
  > { throw SharingProbeFailure.stale }
  func display(on lease: GatewayConnectionLease?, conversations: [String], revision: UUID) throws
    -> PhoneRetainedDisplay
  { throw SharingProbeFailure.stale }
  func suspend() {}
  func close() {}
}

private actor SharingProductProbe: GatewayConversationSharingProviding {
  let source: AuthenticatedGatewaySession
  var grants: [PhoneConversationShare] = []
  var calls: [PhoneConversationShareIntent] = []
  var lost = false
  var queries = 0
  var wrongAck = false
  func mismatchAck() { wrongAck = true }
  init(_ source: AuthenticatedGatewaySession) { self.source = source }
  func setLost() { lost = true }
  func setExisting() {
    grants = [
      .init(
        credentialId: "native-credential", capabilities: ["read", "comment", "drive"],
        policy: .init(preset: "all", allow: nil, deny: nil), policyRevision: 5, grantedAtMs: 1)
    ]
  }
  func authenticatedSession(for lease: GatewayConnectionLease) -> AuthenticatedGatewaySession {
    source
  }
  func ownerConversationChoices(on lease: GatewayConnectionLease) throws
    -> PhoneConversationShareReceipt<NessaConversationList>
  { throw SharingProbeFailure.stale }
  func conversationShares(_ id: String, on lease: GatewayConnectionLease)
    -> PhoneConversationShareReceipt<[PhoneConversationShare]>
  {
    queries += 1
    return .init(source: source, value: grants)
  }
  func setConversationRead(_ intent: PhoneConversationShareIntent, on lease: GatewayConnectionLease)
    throws -> PhoneConversationShareReceipt<PhoneConversationShareAcknowledgment>
  {
    calls.append(intent)
    if lost { throw SharingProbeFailure.lost }
    return .init(
      source: source,
      value: .init(
        requestId: wrongAck
          ? UUID().uuidString.lowercased() : intent.requestID.uuidString.lowercased(), applied: true
      ))
  }
}
private func sharingSnapshot() throws -> (
  PhoneProfileSnapshot, AuthenticatedGatewaySession, PhoneSetupContext
) {
  let o = coordinatorOwner(phase: .active)
  let device = GatewayPairingStatus(
    invitationID: o.invitationID, consentID: o.consentID, generation: o.generation,
    consentClass: o.consentClass, grant: o.grant, createdAtMs: o.createdAtMs,
    expiresAtMs: o.expiresAtMs,
    phase: .active, claimedDeviceKey: o.claimedDeviceKey, credentialID: "native-credential",
    receiver: .init(id: "native-receiver", accessEpoch: 99), terminal: nil, cleanupPending: false)
  let profile = exampleProfile(phase: .prepared).recording(
    pairingStatus: device, nativeReceiver: "native-receiver",
    nativeStatus: coordinatorStatus(coordinatorReceipt(phase: .active)), recoveredPurge: nil,
    retired: false)
  let lease = GatewayConnectionLease()
  let source = AuthenticatedGatewaySession(
    connection: lease,
    snapshot: .init(identity: profile.identity, expiresAt: nil, grants: [], methods: []))
  let snapshot = try PhoneProfileSnapshot(
    registry: exampleProfiles(profile), local: coordinatorLocal(issued: true), nativeStatus: nil,
    source: source)
  let context = PhoneSetupContext(
    connection: .init(
      address: profile.productAddress, credential: "not-persisted", instance: profile.instance),
    lease: lease, snapshot: snapshot)
  return (snapshot, source, context)
}
@Test func sharingApplicationObservedDriveNeverReplacesGrant() async throws {
  let (snapshot, source, context) = try sharingSnapshot()
  let product = SharingProductProbe(source)
  await product.setExisting()
  let root = profileTestRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = PhoneConversationShareIntentStore(root: root)
  let action = PhoneConversationSharing(
    product: product, sync: SharingSyncProbe(snapshot), store: store)
  let result = try await action.perform(
    .share(UUID().uuidString.lowercased()), context: context, current: {})
  #expect(result.intent == nil)
  #expect(result.shares?.first?.capabilities.contains("drive") == true)
  #expect(await product.calls.isEmpty)
  #expect(try await store.load(profileID: snapshot.profile.id).isEmpty)
}
@Test func sharingApplicationLostReplyRetainsExactIntentForExplicitRetry() async throws {
  let (snapshot, source, context) = try sharingSnapshot()
  let product = SharingProductProbe(source)
  await product.setLost()
  let root = profileTestRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = PhoneConversationShareIntentStore(root: root)
  let request = UUID()
  let action = PhoneConversationSharing(
    product: product, sync: SharingSyncProbe(snapshot), store: store, makeID: { request })
  let conversation = UUID().uuidString.lowercased()
  do {
    _ = try await action.perform(.share(conversation), context: context, current: {})
    Issue.record("Expected loss")
  } catch let failure as PhoneConversationSharingFailure {
    #expect(failure.underlying is SharingProbeFailure)
    #expect(failure.intent?.requestID == request)
    #expect(failure.acknowledgment == nil)
    #expect(failure.snapshot?.profile.id == snapshot.profile.id)
  }
  let saved = try #require(await store.load(profileID: snapshot.profile.id).first?.intent)
  #expect(saved.owner.credentialID == source.snapshot.identity.credentialID)
  #expect(saved.device.credentialID == "native-credential")
  await #expect(throws: PhoneConversationSharingFailure.self) {
    _ = try await action.perform(.share(conversation), context: context, current: {})
  }
  #expect(await product.calls.count == 1)
  await #expect(throws: PhoneConversationSharingFailure.self) {
    _ = try await action.perform(.retry(saved), context: context, current: {})
  }
  #expect(await product.calls == [saved, saved])
}
private actor SharingMemoryStore: PhoneConversationShareIntentStoring {
  var records: [PhoneConversationShareRecord] = []
  var loadGate: CoordinatorGate?
  func holdLoad(_ gate: CoordinatorGate) { loadGate = gate }
  func load(profileID: UUID) async -> [PhoneConversationShareRecord] {
    if let loadGate { await loadGate.pause() }
    return records.filter { $0.intent.profileID == profileID }
  }
  func save(_ intent: PhoneConversationShareIntent) { records.append(.init(intent: intent)) }
  func acknowledge(
    _ intent: PhoneConversationShareIntent, value: PhoneConversationShareAcknowledgment
  ) {
    if let index = records.firstIndex(where: { $0.intent == intent }) {
      records[index] = .init(intent: intent, acknowledgment: value)
    }
  }
}
private actor SharingCurrentProbe {
  var calls = 0
  let failAt: Int
  init(_ failAt: Int) { self.failAt = failAt }
  func check() throws {
    calls += 1
    if calls == failAt { throw SharingProbeFailure.stale }
  }
}
@Test func sharingApplicationCurrentFenceAfterQuerySaveAndDispatch() async throws {
  // Checks: entry, ready, native observation, query, pending load, durable save, dispatch.
  for stop in [4, 6, 7] {
    let (snapshot, source, context) = try sharingSnapshot()
    let product = SharingProductProbe(source)
    let store = SharingMemoryStore()
    let fence = SharingCurrentProbe(stop)
    let action = PhoneConversationSharing(
      product: product, sync: SharingSyncProbe(snapshot), store: store)
    do {
      _ = try await action.perform(
        .share(UUID().uuidString.lowercased()), context: context,
        current: { try await fence.check() })
      Issue.record("Expected stale context")
    } catch let failure as PhoneConversationSharingFailure {
      #expect(failure.underlying is SharingProbeFailure)
      #expect((failure.acknowledgment != nil) == (stop == 7))
    }
    #expect(await product.calls.count == (stop == 7 ? 1 : 0))
    let records = await store.records
    #expect(records.count == (stop == 4 ? 0 : 1))
    #expect(records.allSatisfy { $0.acknowledgment == nil })
  }
}
@Test func sharingApplicationWrongReadyLeaseCannotObserveOrMutate() async throws {
  let (snapshot, source, _) = try sharingSnapshot()
  let product = SharingProductProbe(source)
  let sync = SharingSyncProbe(snapshot)
  let context = PhoneSetupContext(
    connection: nil, lease: GatewayConnectionLease(), snapshot: snapshot)
  let action = PhoneConversationSharing(product: product, sync: sync, store: SharingMemoryStore())
  await #expect(throws: PhoneConversationSharingFailure.self) {
    _ = try await action.perform(
      .share(UUID().uuidString.lowercased()), context: context, current: {})
  }
  #expect(await sync.calls.isEmpty)
  #expect(await product.calls.isEmpty)
}
@Test func sharingApplicationPassiveNativeSnapshotCannotAuthorizeShare() async throws {
  let (snapshot, source, context) = try sharingSnapshot()
  let passive = try PhoneProfileSnapshot(
    registry: snapshot.registry, local: snapshot.local, nativeStatus: nil, source: nil)
  let product = SharingProductProbe(source)
  let store = SharingMemoryStore()
  let action = PhoneConversationSharing(
    product: product, sync: SharingSyncProbe(passive), store: store)
  await #expect(throws: PhoneConversationSharingFailure.self) {
    _ = try await action.perform(
      .share(UUID().uuidString.lowercased()), context: context, current: {})
  }
  #expect(await product.calls.isEmpty)
  #expect(await store.records.isEmpty)
}
@Test func sharingApplicationSuccessfulReadAcknowledgmentRemainsHistoricalOnly() async throws {
  let (snapshot, source, context) = try sharingSnapshot()
  let product = SharingProductProbe(source)
  let store = SharingMemoryStore()
  let request = UUID()
  let action = PhoneConversationSharing(
    product: product, sync: SharingSyncProbe(snapshot), store: store, makeID: { request })
  let result = try await action.perform(
    .share(UUID().uuidString.lowercased()), context: context, current: {})
  #expect(result.acknowledgment?.applied == true)
  #expect(result.shares?.isEmpty == true)
  #expect(result.intent?.requestID == request)
  #expect(await product.calls.first?.device.credentialID == "native-credential")
  #expect(await store.records.first?.acknowledgment == result.acknowledgment)
  #expect(try await action.pending(profileID: snapshot.profile.id).isEmpty)
}
private actor SharingValidity {
  var valid = true
  func invalidate() { valid = false }
  func check() throws { if !valid { throw SharingProbeFailure.stale } }
}
@Test func sharingApplicationHeldIntentLoadStopsFollowOnReadAndSave() async throws {
  for retry in [false, true] {
    let (snapshot, source, context) = try sharingSnapshot()
    let product = SharingProductProbe(source)
    let store = SharingMemoryStore()
    let gate = CoordinatorGate()
    let validity = SharingValidity()
    let device = try #require(snapshot.profile.pairingStatus)
    let intent = PhoneConversationShareIntent(
      requestID: UUID(), conversationID: UUID().uuidString.lowercased(),
      profileID: snapshot.profile.id, owner: source.snapshot.identity,
      instance: snapshot.profile.instance, device: device)
    if retry { await store.save(intent) }
    await store.holdLoad(gate)
    let action = PhoneConversationSharing(
      product: product, sync: SharingSyncProbe(snapshot), store: store)
    let operation: PhoneConversationSharingOperation =
      retry ? .retry(intent) : .share(intent.conversationID)
    let task = Task {
      try await action.perform(operation, context: context, current: { try await validity.check() })
    }
    await gate.wait()
    await validity.invalidate()
    await gate.release()
    await #expect(throws: PhoneConversationSharingFailure.self) { _ = try await task.value }
    #expect(await product.calls.isEmpty)
    #expect(await product.queries == (retry ? 0 : 1))
    #expect(await store.records.count == (retry ? 1 : 0))
  }
}
@Test func sharingApplicationRetryRefusesChangedOwnerSurfaceOrDevice() async throws {
  for changedOwner in [false, true] {
    let (snapshot, source, context) = try sharingSnapshot()
    let product = SharingProductProbe(source)
    let store = SharingMemoryStore()
    let intent = PhoneConversationShareIntent(
      requestID: UUID(), conversationID: UUID().uuidString.lowercased(),
      profileID: snapshot.profile.id,
      owner: changedOwner
        ? profileIdentity([
          "owner", "owner", "owner", "owner", "replacement-owner-credential", "owner",
        ]) : source.snapshot.identity,
      instance: snapshot.profile.instance,
      device: changedOwner
        ? try #require(snapshot.profile.pairingStatus) : coordinatorOwner(phase: .claimed))
    await store.save(intent)
    let action = PhoneConversationSharing(
      product: product, sync: SharingSyncProbe(snapshot), store: store)
    do {
      _ = try await action.perform(.retry(intent), context: context, current: {})
      Issue.record("Expected changed identity")
    } catch let failure as PhoneConversationSharingFailure {
      #expect(failure.intent == intent)
      #expect(failure.source == source)
    }
    #expect(await product.queries == 0)
    #expect(await product.calls.isEmpty)
  }
}
@Test func sharingApplicationMismatchedAcknowledgmentNeverCompletesIntent() async throws {
  let (snapshot, source, context) = try sharingSnapshot()
  let product = SharingProductProbe(source)
  await product.mismatchAck()
  let store = SharingMemoryStore()
  let action = PhoneConversationSharing(
    product: product, sync: SharingSyncProbe(snapshot), store: store)
  do {
    _ = try await action.perform(
      .share(UUID().uuidString.lowercased()), context: context, current: {})
    Issue.record("Expected invalid response")
  } catch let failure as PhoneConversationSharingFailure {
    #expect(failure.acknowledgment != nil)
    #expect(failure.acknowledgment?.requestId != failure.intent?.requestID.uuidString.lowercased())
    #expect(failure.underlying is NessaGatewayError)
  }
  #expect(await store.records.first?.acknowledgment == nil)
  #expect(await product.queries == 1)
}
