import Foundation
import NessaFeatures
import Testing

private enum SetupProbeFailure: Error, Equatable { case stale, observe }

private actor SetupContextProbe {
  private var valid = true
  func invalidate() { valid = false }
  func check() throws { if !valid { throw SetupProbeFailure.stale } }
}

private actor SetupGatewayProbe: MessagingRepository, AuthenticatedGatewaySessionProviding,
  GatewayPairingManaging
{
  let source: AuthenticatedGatewaySession
  var pendingSource: AuthenticatedGatewaySession
  let invitations: [GatewayPairingStatus]
  var authenticatedLeases: [GatewayConnectionLease] = []
  var pendingLeases: [GatewayConnectionLease] = []
  var readyGate: CoordinatorGate?
  init(source: AuthenticatedGatewaySession, invitations: [GatewayPairingStatus] = []) {
    self.source = source
    pendingSource = source
    self.invitations = invitations
  }
  func mismatchPendingSource(_ source: AuthenticatedGatewaySession) { pendingSource = source }
  func holdReady(_ gate: CoordinatorGate) { readyGate = gate }
  func authenticatedSession(for lease: GatewayConnectionLease) async -> AuthenticatedGatewaySession
  {
    authenticatedLeases.append(lease)
    if let readyGate { await readyGate.pause() }
    return source
  }
  func pendingPairings(on lease: GatewayConnectionLease) -> GatewayPairingReceipt<
    [GatewayPairingStatus]
  > {
    pendingLeases.append(lease)
    return .init(source: pendingSource, value: invitations)
  }
  func createDevice(on lease: GatewayConnectionLease) throws -> GatewayPairingReceipt<
    GatewayPairingCreated
  > {
    throw SetupProbeFailure.stale
  }
  func pairingStatus(_ invitation: Data, on lease: GatewayConnectionLease) throws
    -> GatewayPairingReceipt<GatewayPairingStatus>
  {
    throw SetupProbeFailure.stale
  }
  func approvePairing(_ invitation: Data, deviceKey: Data, on lease: GatewayConnectionLease) throws
    -> GatewayPairingReceipt<GatewayPairingApproval>
  {
    throw SetupProbeFailure.stale
  }
  func cancelPairing(_ invitation: Data, on lease: GatewayConnectionLease) throws
    -> GatewayPairingReceipt<GatewayPairingStatus>
  {
    throw SetupProbeFailure.stale
  }
  func connect(address: String, credential: String, instance: String) {}
  func disconnect() {}
  func list() throws -> NessaConversationList {
    try JSONDecoder().decode(
      NessaConversationList.self, from: Data("{\"conversations\":[],\"complete\":true}".utf8))
  }
  func read(_ id: String) throws -> NessaConversationView { throw SetupProbeFailure.stale }
  func create(agent: String?, model: String?) -> String { "unused" }
  func send(_ text: String, attachments: [DraftAttachment], conversationID: String) -> String {
    "unused"
  }
  func delete(_ conversationID: String) {}
  func listArchived() -> NessaConversationList { .init(conversations: [], complete: true) }
  func setArchived(_ archived: Bool, conversationID: String) {}
  func answer(_ permission: NessaPermission, option: NessaPermission.Option, conversationID: String)
  {}
}

private actor SetupSyncProbe: PhoneSyncRunning {
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
    if failObserve { throw SetupProbeFailure.observe }
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
    throw SetupProbeFailure.stale
  }
  func cataloguePage(after: RetainedEntryKey?, maximum: UInt32) throws -> PhoneScopedRetention<
    RetainedCataloguePage?
  > { throw SetupProbeFailure.stale }
  func transcript(conversation: String, revision: UUID) throws -> PhoneScopedRetention<
    RetainedTranscript
  > { throw SetupProbeFailure.stale }
  func display(on lease: GatewayConnectionLease?, conversations: [String], revision: UUID) throws
    -> PhoneRetainedDisplay
  { throw SetupProbeFailure.stale }
  func suspend() {}
  func close() {}
}

private func setupSnapshot(claimed: Bool = false) throws -> PhoneProfileSnapshot {
  let original = exampleProfile(phase: .prepared)
  let profile =
    claimed
    ? original.recording(
      pairingStatus: coordinatorOwner(phase: .claimed), nativeReceiver: nil,
      nativeStatus: coordinatorStatus(coordinatorReceipt(phase: .claimed)), recoveredPurge: nil,
      retired: false) : original
  return try .init(
    registry: exampleProfiles(profile), local: claimed ? coordinatorLocal(issued: false) : nil,
    nativeStatus: nil, source: nil)
}
private func setupSource(_ snapshot: PhoneProfileSnapshot, lease: GatewayConnectionLease)
  -> AuthenticatedGatewaySession
{
  .init(
    connection: lease,
    snapshot: .init(identity: snapshot.profile.identity, expiresAt: nil, grants: [], methods: []))
}
private func setupContext(_ snapshot: PhoneProfileSnapshot?, lease: GatewayConnectionLease?)
  -> PhoneSetupContext
{
  .init(
    connection: .init(
      address: "ws://selected/session", credential: "ephemeral-fixture", instance: "selected"),
    lease: lease, snapshot: snapshot)
}
private func expectSetupFailure(_ operation: () async throws -> Void, _ expected: PhoneSetupRefusal)
  async
{
  do {
    try await operation()
    Issue.record("Expected setup refusal")
  } catch let failure as PhoneSetupFailure {
    #expect(failure.underlying as? PhoneSetupRefusal == expected)
  } catch { Issue.record("Unexpected failure: \(error)") }
}

@Test func setupFacadePrepareUsesExactReadySourceAndDistinguishesNewFromResume() async throws {
  let original = try setupSnapshot()
  let lease = GatewayConnectionLease()
  let gateway = SetupGatewayProbe(source: setupSource(original, lease: lease))
  let sync = SetupSyncProbe(original)
  let id = UUID()
  let actions = PhoneSetupActions(
    service: MessagingService(repository: gateway), sync: sync, makeID: { id })
  let result = try await actions.perform(
    .prepare(nativeAddress: "127.0.0.1:19744", newProfile: true),
    context: setupContext(original, lease: lease), current: {})
  let desired = try #require(await sync.prepared)
  #expect(desired.id == id && desired.identity == original.profile.identity)
  #expect(desired.productAddress == "ws://selected/session" && desired.instance == "selected")
  #expect(desired.nativeAddress == "127.0.0.1:19744" && desired.phase == .preparing)
  #expect(result.snapshot?.profile.id == id)
  #expect(await sync.credential == "ephemeral-fixture")
  #expect(await gateway.authenticatedLeases == [lease])
  _ = try await actions.perform(
    .prepare(nativeAddress: original.profile.nativeAddress, newProfile: false),
    context: setupContext(original, lease: lease), current: {})
  #expect(await sync.prepared == original.profile)
  #expect(await sync.leases == [lease, lease])
  await expectSetupFailure(
    {
      _ = try await actions.perform(
        .prepare(nativeAddress: "127.0.0.1:1", newProfile: false),
        context: setupContext(original, lease: lease), current: {})
    }, .changedSetup)
  #expect(await sync.calls == ["prepare", "prepare"])
}

@Test func setupFacadeWrongReadyLeaseCannotPrepare() async throws {
  let snapshot = try setupSnapshot()
  let lease = GatewayConnectionLease()
  let gateway = SetupGatewayProbe(source: setupSource(snapshot, lease: .init()))
  let sync = SetupSyncProbe(snapshot)
  let actions = PhoneSetupActions(service: MessagingService(repository: gateway), sync: sync)
  await expectSetupFailure(
    {
      _ = try await actions.perform(
        .prepare(nativeAddress: "127.0.0.1:19744", newProfile: true),
        context: setupContext(snapshot, lease: lease), current: {})
    }, .changed)
  #expect(await sync.calls.isEmpty)
}

@Test func setupFacadeContextChangeAfterReadyStopsPreparation() async throws {
  let snapshot = try setupSnapshot()
  let lease = GatewayConnectionLease()
  let gate = CoordinatorGate()
  let context = SetupContextProbe()
  let gateway = SetupGatewayProbe(source: setupSource(snapshot, lease: lease))
  await gateway.holdReady(gate)
  let sync = SetupSyncProbe(snapshot)
  let actions = PhoneSetupActions(service: MessagingService(repository: gateway), sync: sync)
  let preparing = Task {
    try await actions.perform(
      .prepare(nativeAddress: "127.0.0.1:19744", newProfile: true),
      context: setupContext(snapshot, lease: lease), current: { try await context.check() })
  }
  await gate.wait()
  await context.invalidate()
  await gate.release()
  do {
    _ = try await preparing.value
    Issue.record("Stale preparation advanced")
  } catch let failure as PhoneSetupFailure {
    #expect(failure.underlying as? SetupProbeFailure == .stale)
    #expect(
      failure.source?.connection == lease && failure.snapshot?.profile.id == snapshot.profile.id)
  }
  #expect(await sync.calls.isEmpty)
}

@Test func setupFacadePairObservesExactClaimWithoutImplicitApprovalAndFencesFollowOn() async throws
{
  let snapshot = try setupSnapshot(claimed: true)
  let lease = GatewayConnectionLease()
  let gateway = SetupGatewayProbe(source: setupSource(snapshot, lease: lease))
  let sync = SetupSyncProbe(snapshot)
  let actions = PhoneSetupActions(service: MessagingService(repository: gateway), sync: sync)
  let paired = try await actions.perform(
    .pair, context: setupContext(snapshot, lease: lease), current: {})
  #expect(paired.snapshot?.confirmation == snapshot.confirmation)
  #expect(await sync.calls == ["pair", "observe"])
  #expect(await sync.leases == [lease, lease])
  let gate = CoordinatorGate()
  let context = SetupContextProbe()
  await sync.holdPair(gate)
  let pairing = Task {
    try await actions.perform(
      .pair, context: setupContext(snapshot, lease: lease), current: { try await context.check() })
  }
  await gate.wait()
  await context.invalidate()
  await gate.release()
  do {
    _ = try await pairing.value
    Issue.record("Stale pair followed on")
  } catch let failure as PhoneSetupFailure {
    #expect(failure.underlying as? SetupProbeFailure == .stale)
    #expect(failure.snapshot?.confirmation == snapshot.confirmation)
  }
  #expect(await sync.calls == ["pair", "observe", "pair"])
}

@Test func setupFacadeApprovalRequiresDisplayedConfirmation() async throws {
  let snapshot = try setupSnapshot(claimed: true)
  let lease = GatewayConnectionLease()
  let sync = SetupSyncProbe(snapshot)
  let actions = PhoneSetupActions(
    service: MessagingService(
      repository: SetupGatewayProbe(source: setupSource(snapshot, lease: lease))), sync: sync)
  let confirmation = try #require(snapshot.confirmation)
  let changed = PhonePairingConfirmation(
    profileID: confirmation.profileID, invitation: confirmation.invitation,
    deviceKey: Data(repeating: 9, count: 32))
  await expectSetupFailure(
    {
      _ = try await actions.perform(
        .approve(changed), context: setupContext(snapshot, lease: lease), current: {})
    }, .changed)
  #expect(await sync.calls.isEmpty)
  _ = try await actions.perform(
    .approve(confirmation), context: setupContext(snapshot, lease: lease), current: {})
  #expect(await sync.confirmation == confirmation)
  #expect(await sync.leases == [lease])
}

@Test func setupFacadePendingRecoveryKeepsOwnerSourceAndExplicitSelectedTarget() async throws {
  let snapshot = try setupSnapshot()
  let lease = GatewayConnectionLease()
  let first = coordinatorOwner()
  let template = coordinatorOwner(phase: .claimed)
  let second = GatewayPairingStatus(
    invitationID: Data(repeating: 8, count: 16), consentID: template.consentID,
    generation: template.generation, consentClass: template.consentClass, grant: template.grant,
    createdAtMs: template.createdAtMs, expiresAtMs: template.expiresAtMs, phase: template.phase,
    claimedDeviceKey: template.claimedDeviceKey, credentialID: template.credentialID,
    receiver: template.receiver, terminal: template.terminal,
    cleanupPending: template.cleanupPending)
  let gateway = SetupGatewayProbe(
    source: setupSource(snapshot, lease: lease), invitations: [first, second])
  let sync = SetupSyncProbe(snapshot)
  let actions = PhoneSetupActions(service: MessagingService(repository: gateway), sync: sync)
  let pending = try await actions.perform(
    .findInvitations, context: setupContext(snapshot, lease: lease), current: {})
  #expect(pending.invitations == [first, second])
  #expect(await sync.calls.isEmpty)
  let selected = second.invitationID
  #expect(selected != first.invitationID)
  _ = try await actions.perform(
    .recover(selected), context: setupContext(snapshot, lease: lease), current: {})
  #expect(await sync.recovered == selected)
  #expect(await sync.calls == ["recover"])
  await gateway.mismatchPendingSource(setupSource(snapshot, lease: .init()))
  await expectSetupFailure(
    {
      _ = try await actions.perform(
        .findInvitations, context: setupContext(snapshot, lease: lease), current: {})
    }, .changed)
  #expect(await sync.calls == ["recover"])
}

@Test func setupFacadeOfflineRestoreAndDiscardDoNotContactProductOwner() async throws {
  let snapshot = try setupSnapshot()
  let gateway = SetupGatewayProbe(source: setupSource(snapshot, lease: .init()))
  let sync = SetupSyncProbe(snapshot)
  let actions = PhoneSetupActions(service: MessagingService(repository: gateway), sync: sync)
  for operation: PhoneSetupOperation in [.restore, .discard] {
    let result = try await actions.perform(
      operation, context: .init(connection: nil, lease: nil, snapshot: snapshot), current: {})
    #expect(result.snapshot?.registry == snapshot.registry)
  }
  #expect(await gateway.authenticatedLeases.isEmpty)
  #expect(await gateway.pendingLeases.isEmpty)
  #expect(await sync.calls == ["restore", "discard"])
}

@Test func setupFacadeObserveFailurePreservesAdmittedPairSnapshot() async throws {
  let snapshot = try setupSnapshot(claimed: true)
  let lease = GatewayConnectionLease()
  let gateway = SetupGatewayProbe(source: setupSource(snapshot, lease: lease))
  let sync = SetupSyncProbe(snapshot)
  await sync.failingObserve()
  let actions = PhoneSetupActions(service: MessagingService(repository: gateway), sync: sync)
  do {
    _ = try await actions.perform(.pair, context: setupContext(nil, lease: lease), current: {})
    Issue.record("Failure became success")
  } catch let failure as PhoneSetupFailure {
    #expect(failure.underlying as? SetupProbeFailure == .observe)
    #expect(failure.snapshot?.registry == snapshot.registry)
    #expect(failure.snapshot?.confirmation == snapshot.confirmation)
  }
  #expect(await sync.calls == ["pair", "observe"])
}
