import Foundation
import NessaFeatures
import Testing

private func vmSetupList(_ id: String) throws -> NessaConversationList {
  try JSONDecoder().decode(
    NessaConversationList.self,
    from: Data(
      "{\"conversations\":[{\"conversationId\":\"\(id)\",\"updatedAtMs\":1,\"running\":false}],\"complete\":true}"
        .utf8))
}
private func vmSetupView(_ id: String) throws -> NessaConversationView {
  try JSONDecoder().decode(
    NessaConversationView.self,
    from: Data(
      "{\"conversationId\":\"\(id)\",\"messages\":[],\"permissions\":[],\"truncated\":false}".utf8))
}
private func vmSetupSnapshot(claimed: Bool = false) throws -> PhoneProfileSnapshot {
  let profile = exampleProfile(phase: .prepared).recording(
    pairingStatus: claimed ? coordinatorOwner(phase: .claimed) : nil,
    nativeReceiver: "native-receiver", nativeStatus: nil, recoveredPurge: nil, retired: false)
  return try .init(
    registry: exampleProfiles(profile), local: claimed ? coordinatorLocal(issued: false) : nil,
    nativeStatus: nil, source: nil)
}

private actor VMSetupSnapshots: PhoneSnapshotStoring {
  var loads = 0
  var saves = 0
  func load(_ scope: PhoneCacheScope) throws -> PhoneSnapshot? {
    loads += 1
    var value = PhoneSnapshot()
    value.list = try vmSetupList("legacy-cache")
    return value
  }
  func save(_ value: PhoneSnapshot, scope: PhoneCacheScope) { saves += 1 }
}
private actor VMSetupGateway: MessagingRepository, ConnectionLeasing,
  AuthenticatedGatewaySessionProviding, GatewayPairingManaging
{
  let identity: GatewaySessionSnapshot.Identity
  private var lease: GatewayConnectionLease?
  var connections: [String] = []
  var lists = 0
  var reads = 0
  var sends = 0
  var readyLeases: [GatewayConnectionLease] = []
  var invitations: [GatewayPairingStatus] = [coordinatorOwner()]
  func setInvitations(_ values: [GatewayPairingStatus]) { invitations = values }
  var readGate: CoordinatorGate?
  var pendingGate: CoordinatorGate?
  var pendingRequests = 0
  func holdPending(_ gate: CoordinatorGate) { pendingGate = gate }
  func holdRead(_ gate: CoordinatorGate) { readGate = gate }
  init(identity: GatewaySessionSnapshot.Identity) { self.identity = identity }
  func connect(address: String, credential: String, instance: String) {
    connections.append(address)
  }
  func connectWithLease(address: String, credential: String, instance: String)
    -> GatewayConnectionLease
  {
    connections.append(address)
    let value = GatewayConnectionLease()
    lease = value
    return value
  }
  func retire(_ value: GatewayConnectionLease) { if lease == value { lease = nil } }
  func disconnect() { lease = nil }
  func authenticatedSession(for value: GatewayConnectionLease) throws -> AuthenticatedGatewaySession
  {
    guard value == lease else { throw NessaGatewayError.disconnected }
    readyLeases.append(value)
    return .init(
      connection: value,
      snapshot: .init(identity: identity, expiresAt: nil, grants: [], methods: []))
  }
  func pendingPairings(on value: GatewayConnectionLease) async throws -> GatewayPairingReceipt<
    [GatewayPairingStatus]
  > {
    let source = try authenticatedSession(for: value)
    let captured = invitations
    pendingRequests += 1
    if let pendingGate { await pendingGate.pause() }
    return .init(source: source, value: captured)
  }
  func createDevice(on lease: GatewayConnectionLease) throws -> GatewayPairingReceipt<
    GatewayPairingCreated
  > { throw NessaGatewayError.disconnected }
  func pairingStatus(_ invitation: Data, on lease: GatewayConnectionLease) throws
    -> GatewayPairingReceipt<GatewayPairingStatus>
  { throw NessaGatewayError.disconnected }
  func approvePairing(_ invitation: Data, deviceKey: Data, on lease: GatewayConnectionLease) throws
    -> GatewayPairingReceipt<GatewayPairingApproval>
  { throw NessaGatewayError.disconnected }
  func cancelPairing(_ invitation: Data, on lease: GatewayConnectionLease) throws
    -> GatewayPairingReceipt<GatewayPairingStatus>
  { throw NessaGatewayError.disconnected }
  func list() throws -> NessaConversationList {
    lists += 1
    return try vmSetupList("legacy-product")
  }
  func read(_ id: String) async throws -> NessaConversationView {
    reads += 1
    if let readGate { await readGate.pause() }
    return try vmSetupView(id)
  }
  func create(agent: String?, model: String?) -> String { "unused" }
  func send(_ text: String, attachments: [DraftAttachment], conversationID: String) -> String {
    sends += 1
    return "turn"
  }
  func delete(_ conversationID: String) {}
  func listArchived() throws -> NessaConversationList {
    try JSONDecoder().decode(
      NessaConversationList.self, from: Data("{\"conversations\":[],\"complete\":true}".utf8))
  }
  func setArchived(_ archived: Bool, conversationID: String) {}
  func answer(_ permission: NessaPermission, option: NessaPermission.Option, conversationID: String)
  {}
}

private actor VMSetupSync: PhoneSyncRunning {
  var snapshot: PhoneProfileSnapshot?
  var calls: [String] = []
  var displays = 0
  var starts = 0
  var suspends = 0
  var prepared: PhoneProfile?
  var recovered: Data?
  var confirmation: PhonePairingConfirmation?
  var actionLease: GatewayConnectionLease?
  var pairGate: CoordinatorGate?
  var displayGate: CoordinatorGate?
  var positiveDisplay = true
  var pairFailure: (any Error)?
  private var pairActive = false
  private var drainWaiters: [CheckedContinuation<Void, Never>] = []
  init(_ snapshot: PhoneProfileSnapshot?) { self.snapshot = snapshot }
  func holdPair(_ gate: CoordinatorGate) { pairGate = gate }
  func holdDisplay(_ gate: CoordinatorGate) { displayGate = gate }
  func statusOnly() { positiveDisplay = false }
  func failPair(_ error: any Error, saved: PhoneProfileSnapshot) {
    pairFailure = error
    snapshot = saved
  }
  func startup() -> PhoneSyncStartup? {
    starts += 1
    guard let snapshot else { return nil }
    return .init(
      snapshot: snapshot,
      connection: .init(
        address: snapshot.profile.productAddress, credential: "fixture",
        instance: snapshot.profile.instance))
  }
  func savedProfiles() -> PhoneProfiles? { snapshot?.registry }
  func restore() -> PhoneProfileSnapshot? {
    calls.append("restore")
    return snapshot
  }
  func prepare(_ desired: PhoneProfile, credential: String, on lease: GatewayConnectionLease) throws
    -> PhoneProfileSnapshot
  {
    calls.append("prepare")
    prepared = desired
    actionLease = lease
    let result = try PhoneProfileSnapshot(
      registry: exampleProfiles(desired.changingPhase(to: .prepared)), local: nil,
      nativeStatus: nil, source: nil)
    snapshot = result
    return result
  }
  func startPairing(on lease: GatewayConnectionLease) async throws -> PhoneProfileSnapshot {
    calls.append("pair")
    actionLease = lease
    pairActive = true
    defer {
      pairActive = false
      for waiter in drainWaiters { waiter.resume() }
      drainWaiters = []
    }
    if let pairGate { await pairGate.pause() }
    if let pairFailure { throw pairFailure }
    return try #require(snapshot)
  }
  func observePairing(on lease: GatewayConnectionLease) throws -> PhoneProfileSnapshot {
    calls.append("observe")
    actionLease = lease
    return try #require(snapshot)
  }
  func approve(_ confirmation: PhonePairingConfirmation, on lease: GatewayConnectionLease) throws
    -> PhoneProfileSnapshot
  {
    calls.append("approve")
    self.confirmation = confirmation
    actionLease = lease
    return try #require(snapshot)
  }
  func resolveInvitation(_ invitation: Data, on lease: GatewayConnectionLease) throws
    -> PhoneProfileSnapshot
  {
    calls.append("recover")
    recovered = invitation
    actionLease = lease
    return try #require(snapshot)
  }
  func cancelPairing(on lease: GatewayConnectionLease) throws -> PhoneProfileSnapshot {
    calls.append("cancel")
    return try #require(snapshot)
  }
  func discardUnenrolled() throws -> PhoneProfileSnapshot {
    calls.append("discard")
    return try #require(snapshot)
  }
  func refresh(on lease: GatewayConnectionLease?) throws -> PhoneProfileSnapshot {
    throw NessaGatewayError.disconnected
  }
  func cataloguePage(after: RetainedEntryKey?, maximum: UInt32) throws -> PhoneScopedRetention<
    RetainedCataloguePage?
  > { throw NessaGatewayError.disconnected }
  func transcript(conversation: String, revision: UUID) throws -> PhoneScopedRetention<
    RetainedTranscript
  > { throw NessaGatewayError.disconnected }
  func display(on lease: GatewayConnectionLease?, conversations: [String], revision: UUID)
    async throws -> PhoneRetainedDisplay
  {
    displays += 1
    if let displayGate { await displayGate.pause() }
    let saved = try #require(snapshot)
    let status = coordinatorStatus(coordinatorReceipt(phase: .active))
    let refresh = RetainedRefresh(
      initial: status,
      read: positiveDisplay
        ? .init(complete: true, conversations: 1, failure: nil, moved: false, withdrawn: []) : nil,
      recheck: nil, selectionFailure: nil)
    let source = lease.map {
      AuthenticatedGatewaySession(
        connection: $0,
        snapshot: .init(identity: saved.profile.identity, expiresAt: nil, grants: [], methods: []))
    }
    let observed = try PhoneProfileSnapshot(
      registry: saved.registry, local: saved.local, nativeStatus: status, source: source,
      nativeRefresh: refresh)
    let scope = RetainedScope(
      accessEpoch: "99", incarnation: "one", origin: "owner", receiver: "native-receiver",
      schema: "1", stream: "catalogue")
    let page = RetainedCataloguePage(
      activeBoundary: nil, activeCursor: nil, completed: 1, entries: [], generation: 1, next: nil,
      scope: scope)
    var transcripts: [String: PhoneRetainedTranscriptRead] = [:]
    for id in conversations {
      let view = try vmSetupView(id)
      transcripts[id] = .available(
        .init(
          profileID: saved.profile.id, revision: saved.registry.revision,
          value: .init(
            state: .retained, scope: scope, downloaded: 1, applied: 1, facts: 1, generation: 1,
            view: .available(
              .init(
                json: Data(), revision: revision.uuidString, revisionEpoch: revision, display: view)
            ))))
    }
    return .init(
      snapshot: observed,
      catalogue: .init(
        profileID: saved.profile.id, revision: saved.registry.revision, pages: [page],
        list: try vmSetupList("native")), transcripts: transcripts, refreshFailure: nil)
  }
  func suspend() async {
    suspends += 1
    if pairActive { await withCheckedContinuation { drainWaiters.append($0) } }
  }
  func close() async { await suspend() }
}

@MainActor private func vmSetupModel(
  _ sync: VMSetupSync, _ gateway: VMSetupGateway, _ snapshots: VMSetupSnapshots,
  recovery: ConnectionRecovery? = nil
) -> MessagesViewModel {
  .init(
    service: MessagingService(repository: gateway), credentials: InMemoryCredentialStore(),
    preferences: InMemoryChatPreferences(),
    snapshots: PhoneSnapshotSession(store: snapshots, coalescingDelay: .zero), recovery: recovery,
    phoneSync: sync)
}
@MainActor private func vmSetupConnect(_ model: MessagesViewModel) async {
  await model.connect(address: "mock://product", credential: "fixture", instance: "phone")
}

@Test @MainActor func setupVMRequiresReadyAndForwardsExactSourceBeforeFreshPreparation()
  async throws
{
  let saved = try vmSetupSnapshot()
  let sync = VMSetupSync(nil)
  let gateway = VMSetupGateway(identity: saved.profile.identity)
  let model = vmSetupModel(sync, gateway, VMSetupSnapshots())
  #expect(
    !(await model.performPhoneSetup(.prepare(nativeAddress: "127.0.0.1:19744", newProfile: true))))
  #expect(await sync.calls.isEmpty)
  await vmSetupConnect(model)
  let lease = try #require(model.acceptedLease)
  #expect(
    await model.performPhoneSetup(.prepare(nativeAddress: "127.0.0.1:19744", newProfile: true)))
  let prepared = try #require(await sync.prepared)
  #expect(prepared.identity == saved.profile.identity && prepared.id != saved.profile.id)
  #expect(prepared.productAddress == "mock://product" && prepared.instance == "phone")
  #expect(await sync.actionLease == lease)
  #expect(await gateway.readyLeases == [lease])
  #expect(!model.conversationAuthorityReady)
  await model.suspendConnection()
}

@Test @MainActor func setupVMFencesHeldNativeDisplayBeforePreparingAndRejectsSecondOperation()
  async throws
{
  let saved = try vmSetupSnapshot()
  let sync = VMSetupSync(saved)
  let gateway = VMSetupGateway(identity: saved.profile.identity)
  let snapshots = VMSetupSnapshots()
  let model = vmSetupModel(sync, gateway, snapshots)
  await vmSetupConnect(model)
  await model.refresh("native")
  #expect(model.canSubmit(in: "native"))
  let gate = CoordinatorGate()
  await sync.holdDisplay(gate)
  let reading = Task { await model.refresh("native") }
  await gate.wait()
  let setup = Task {
    await model.performPhoneSetup(.prepare(nativeAddress: "127.0.0.1:19744", newProfile: true))
  }
  for _ in 0..<2000 {
    if model.phoneSetupBusy { break }
    await Task.yield()
  }
  #expect(model.phoneSetupBusy && model.views.isEmpty && model.conversations.isEmpty)
  #expect(!model.canSubmit(in: "native"))
  #expect(!(await model.send("old", to: "native")))
  #expect(!(await model.performPhoneSetup(.observe)))
  #expect(await sync.prepared == nil)
  await gate.release()
  await reading.value
  #expect(await setup.value)
  #expect(await sync.calls == ["prepare"])
  #expect(model.views.isEmpty)
  #expect(await snapshots.loads == 0)
  #expect(await snapshots.saves == 0)
  #expect(await gateway.sends == 0)
  await model.suspendConnection()
}

@Test @MainActor func setupVMOwnsPairAcrossCancelledObserverAndNeverApprovesAutomatically()
  async throws
{
  let saved = try vmSetupSnapshot(claimed: true)
  let sync = VMSetupSync(saved)
  let gateway = VMSetupGateway(identity: saved.profile.identity)
  let model = vmSetupModel(sync, gateway, VMSetupSnapshots())
  await vmSetupConnect(model)
  let gate = CoordinatorGate()
  await sync.holdPair(gate)
  let observer = Task { await model.performPhoneSetup(.pair) }
  await gate.wait()
  observer.cancel()
  #expect(model.phoneSetupBusy && !model.conversationAuthorityReady)
  #expect(!(await model.performPhoneSetup(.pair)))
  await gate.release()
  #expect(await observer.value)
  #expect(await sync.calls == ["pair", "observe"])
  #expect(!model.phoneSetupBusy)
  #expect(model.phoneProfile?.confirmation == saved.confirmation)
  await model.suspendConnection()
}

@Test @MainActor func setupVMExplicitConfirmationAndRecoveryPassThroughFacade() async throws {
  let saved = try vmSetupSnapshot(claimed: true)
  let sync = VMSetupSync(saved)
  let gateway = VMSetupGateway(identity: saved.profile.identity)
  let model = vmSetupModel(sync, gateway, VMSetupSnapshots())
  await vmSetupConnect(model)
  let confirmation = try #require(saved.confirmation)
  let changed = PhonePairingConfirmation(
    profileID: confirmation.profileID, invitation: confirmation.invitation,
    deviceKey: Data(repeating: 9, count: 32))
  #expect(!(await model.performPhoneSetup(.approve(changed))))
  #expect(await sync.confirmation == nil)
  #expect(await model.performPhoneSetup(.approve(confirmation)))
  #expect(await sync.confirmation == confirmation)
  let first = coordinatorOwner()
  let second = GatewayPairingStatus(
    invitationID: Data(repeating: 8, count: 16), consentID: Data(repeating: 9, count: 16),
    generation: first.generation, consentClass: first.consentClass, grant: first.grant,
    createdAtMs: first.createdAtMs, expiresAtMs: first.expiresAtMs, phase: first.phase,
    claimedDeviceKey: first.claimedDeviceKey, credentialID: first.credentialID,
    receiver: first.receiver, terminal: first.terminal, cleanupPending: first.cleanupPending)
  await gateway.setInvitations([first, second])
  #expect(await model.performPhoneSetup(.findInvitations))
  #expect(model.phoneInvitations == [first, second])
  let chosen = second.invitationID
  #expect(chosen != first.invitationID)
  #expect(await model.performPhoneSetup(.recover(chosen)))
  #expect(await sync.recovered == chosen)
  await model.suspendConnection()
}

@Test @MainActor func setupVMManualReplacementWaitsForOwnedPairAndRejectsOldFollowOn() async throws
{
  let saved = try vmSetupSnapshot(claimed: true)
  let sync = VMSetupSync(saved)
  let gateway = VMSetupGateway(identity: saved.profile.identity)
  let model = vmSetupModel(sync, gateway, VMSetupSnapshots())
  await vmSetupConnect(model)
  let oldLease = try #require(model.acceptedLease)
  let gate = CoordinatorGate()
  await sync.holdPair(gate)
  let pairing = Task { await model.performPhoneSetup(.pair) }
  await gate.wait()
  let replacement = Task {
    await model.connect(address: "mock://new", credential: "new", instance: "new")
  }
  for _ in 0..<2000 {
    if model.currentGatewayAddress == "mock://new" { break }
    await Task.yield()
  }
  #expect(model.views.isEmpty && model.conversations.isEmpty)
  #expect(await gateway.connections == ["mock://product"])
  await gate.release()
  #expect(!(await pairing.value))
  await replacement.value
  #expect(await sync.calls == ["pair"])
  #expect(await gateway.connections == ["mock://product", "mock://new"])
  #expect(model.acceptedLease != oldLease)
  #expect(!model.phoneSetupBusy)
  await model.suspendConnection()
}

@Test @MainActor func setupVMBackgroundDrainsOwnedPairBeforeForegroundReopen() async throws {
  let saved = try vmSetupSnapshot(claimed: true)
  let sync = VMSetupSync(saved)
  let gateway = VMSetupGateway(identity: saved.profile.identity)
  let recovery = ConnectionRecovery(waiting: SystemRecoveryWait())
  let model = vmSetupModel(sync, gateway, VMSetupSnapshots(), recovery: recovery)
  await model.connect(
    address: "unused", credential: "", instance: "unused", restoringSavedProfile: true)
  let gate = CoordinatorGate()
  await sync.holdPair(gate)
  let pairing = Task { await model.performPhoneSetup(.pair) }
  await gate.wait()
  let background = Task { await model.suspendConnection() }
  for _ in 0..<2000 {
    if await sync.suspends == 1 { break }
    await Task.yield()
  }
  #expect(!model.connected && model.acceptedLease == nil)
  #expect(!(await model.performPhoneSetup(.observe)))
  #expect(model.phoneSetupBusy)
  await gate.release()
  #expect(!(await pairing.value))
  await background.value
  #expect(!model.phoneSetupBusy)
  #expect(await sync.calls == ["pair"])
  model.resumeConnection()
  for _ in 0..<4000 {
    if model.connected { break }
    await Task.yield()
  }
  #expect(model.connected)
  #expect(await sync.starts == 2)
  await model.suspendConnection()
}

@Test @MainActor func setupVMFailureKeepsActualSavedRegistryAndNestedNativeEvidence() async throws {
  let saved = try vmSetupSnapshot(claimed: true)
  let sync = VMSetupSync(saved)
  let gateway = VMSetupGateway(identity: saved.profile.identity)
  let snapshots = VMSetupSnapshots()
  let model = vmSetupModel(sync, gateway, snapshots)
  await vmSetupConnect(model)
  let nextRegistry = PhoneProfiles(
    revision: UUID(), selected: saved.profile.id, profiles: saved.registry.profiles)
  let latest = try PhoneProfileSnapshot(
    registry: nextRegistry, local: saved.local, nativeStatus: nil, source: nil)
  let native = coordinatorStatus(coordinatorReceipt(phase: .claimed))
  let coordination = PhoneProfileCoordinationFailure(
    operation: UUID(), profileID: saved.profile.id, source: nil,
    owner: coordinatorOwner(phase: .claimed), nativeStatus: native,
    underlying: PhoneProfileStoreError.write(.published, .unavailable, reconciliation: nil),
    local: saved.local)
  let wrapped = PhoneSyncRuntimeFailure(
    operation: UUID(), snapshot: latest, underlying: coordination)
  await sync.failPair(wrapped, saved: latest)
  #expect(!(await model.performPhoneSetup(.pair)))
  #expect(model.phoneProfile?.registry == nextRegistry)
  #expect(model.phoneProfile?.nativeStatus == native)
  #expect(model.phoneProfile?.local == saved.local)
  let setup = try #require(model.phoneSyncFailure as? PhoneSetupFailure)
  let runtime = try #require(setup.underlying as? PhoneSyncRuntimeFailure)
  #expect((runtime.underlying as? PhoneProfileCoordinationFailure)?.nativeStatus == native)
  #expect(!model.nativeHistoryReady && !model.nativeCommandReady && model.conversations.isEmpty)
  #expect(await snapshots.loads == 0)
  #expect(await gateway.lists == 0)
  await model.suspendConnection()
}

@Test @MainActor func setupVMStatusOnlyApprovalCannotEnableCommandsWithoutPositiveNativeDisplay()
  async throws
{
  let saved = try vmSetupSnapshot(claimed: true)
  let sync = VMSetupSync(saved)
  let gateway = VMSetupGateway(identity: saved.profile.identity)
  let model = vmSetupModel(sync, gateway, VMSetupSnapshots())
  await vmSetupConnect(model)
  await sync.statusOnly()
  #expect(await model.performPhoneSetup(.approve(try #require(saved.confirmation))))
  #expect(model.nativeHistoryReady && !model.nativeCommandReady)
  #expect(model.connected && !model.canSubmit(in: "native"))
  #expect(!(await model.send("not confirmed", to: "native")))
  #expect(await gateway.sends == 0)
  await model.suspendConnection()
}

@Test @MainActor func setupVMRejectsLateLegacyReadAndSnapshotWriteAfterNativePreparation()
  async throws
{
  let saved = try vmSetupSnapshot()
  let sync = VMSetupSync(nil)
  let gateway = VMSetupGateway(identity: saved.profile.identity)
  let store = VMSetupSnapshots()
  let writer = PhoneSnapshotSession(store: store, coalescingDelay: .zero)
  let model = MessagesViewModel(
    service: MessagingService(repository: gateway), credentials: InMemoryCredentialStore(),
    preferences: InMemoryChatPreferences(), snapshots: writer, phoneSync: sync)
  await vmSetupConnect(model)
  #expect(model.conversations.map(\.id) == ["legacy-product"])
  await writer.flush()
  let priorSaves = await store.saves
  let gate = CoordinatorGate()
  await gateway.holdRead(gate)
  let reading = Task { await model.refresh("legacy-product") }
  await gate.wait()
  #expect(
    await model.performPhoneSetup(.prepare(nativeAddress: "127.0.0.1:19744", newProfile: true)))
  #expect(
    model.conversations.isEmpty && model.views.isEmpty && !model.canSubmit(in: "legacy-product"))
  await gate.release()
  await reading.value
  await writer.flush()
  #expect(model.views.isEmpty)
  #expect(await store.saves == priorSaves)
  await model.suspendConnection()
}

@Test @MainActor func setupVMCancelledBeforeAdmissionCannotFenceOrStartAnOperation() async throws {
  let saved = try vmSetupSnapshot(claimed: true)
  let sync = VMSetupSync(saved)
  let gateway = VMSetupGateway(identity: saved.profile.identity)
  let model = vmSetupModel(sync, gateway, VMSetupSnapshots())
  await vmSetupConnect(model)
  await model.refresh("native")
  let originalLease = model.acceptedLease
  let originalRows = model.conversations
  let originalRevision = model.connectionRevision
  let originalScope = model.deliveryScopeRevision
  let gate = CoordinatorGate()
  let observer = Task {
    await gate.pause()
    return await model.performPhoneSetup(.pair)
  }
  await gate.wait()
  observer.cancel()
  await gate.release()
  #expect(!(await observer.value))
  #expect(await sync.calls.isEmpty)
  #expect(!model.phoneSetupBusy && model.nativeCommandReady)
  #expect(model.conversations == originalRows && model.views["native"] != nil)
  #expect(model.acceptedLease == originalLease)
  #expect(
    model.connectionRevision == originalRevision && model.deliveryScopeRevision == originalScope)
  await model.suspendConnection()
}

@Test @MainActor func setupVMLatePendingReceiptCannotPublishAfterManualReplacement() async throws {
  let saved = try vmSetupSnapshot()
  let sync = VMSetupSync(saved)
  let gateway = VMSetupGateway(identity: saved.profile.identity)
  let model = vmSetupModel(sync, gateway, VMSetupSnapshots())
  await vmSetupConnect(model)
  let oldLease = try #require(model.acceptedLease)
  let gate = CoordinatorGate()
  await gateway.holdPending(gate)
  let finding = Task { await model.performPhoneSetup(.findInvitations) }
  await gate.wait()
  #expect(model.phoneSetupBusy && model.phoneInvitations.isEmpty)
  let replacing = Task {
    await model.connect(address: "mock://other", credential: "other", instance: "other")
  }
  for _ in 0..<2000 {
    if model.currentGatewayAddress == "mock://other" { break }
    await Task.yield()
  }
  #expect(await gateway.connections == ["mock://product"])
  await gate.release()
  #expect(!(await finding.value))
  await replacing.value
  #expect(model.phoneInvitations.isEmpty && !model.phoneSetupBusy)
  #expect(await sync.calls.isEmpty)
  #expect(await gateway.pendingRequests == 1)
  #expect(model.acceptedLease != oldLease)
  await model.suspendConnection()
}

private actor VMSetupCurrentProbe {
  private var valid = true
  func invalidate() { valid = false }
  func check() throws { if !valid { throw PhoneSetupRefusal.changed } }
}

@Test func setupVMPendingFacadeChecksCurrentContextBeforeReturningCapturedInvitations() async throws
{
  let saved = try vmSetupSnapshot()
  let sync = VMSetupSync(saved)
  let gateway = VMSetupGateway(identity: saved.profile.identity)
  let lease = await gateway.connectWithLease(
    address: "mock://product", credential: "fixture", instance: "phone")
  let gate = CoordinatorGate()
  let current = VMSetupCurrentProbe()
  await gateway.holdPending(gate)
  let actions = PhoneSetupActions(service: MessagingService(repository: gateway), sync: sync)
  let context = PhoneSetupContext(connection: nil, lease: lease, snapshot: saved)
  let finding = Task {
    try await actions.perform(.findInvitations, context: context) { try await current.check() }
  }
  await gate.wait()
  await current.invalidate()
  await gate.release()
  do {
    _ = try await finding.value
    Issue.record("Old-context invitation receipt escaped the facade")
  } catch let failure as PhoneSetupFailure {
    #expect(failure.underlying as? PhoneSetupRefusal == .changed)
    #expect(failure.source?.connection == lease && failure.snapshot?.registry == saved.registry)
  }
  #expect(await sync.calls.isEmpty)
}
