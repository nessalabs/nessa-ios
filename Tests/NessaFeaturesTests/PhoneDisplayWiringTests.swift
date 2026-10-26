import Foundation
import NessaFeatures
import Testing

private func displayDecode<Value: Decodable>(_ type: Value.Type, _ json: String) throws -> Value {
  try JSONDecoder().decode(type, from: Data(json.utf8))
}
private func displayList(_ id: String) throws -> NessaConversationList {
  try displayDecode(
    NessaConversationList.self,
    "{\"conversations\":[{\"conversationId\":\"\(id)\",\"updatedAtMs\":1,\"running\":false}],\"complete\":true}"
  )
}
private func displayView(_ id: String) throws -> NessaConversationView {
  try displayDecode(
    NessaConversationView.self,
    "{\"conversationId\":\"\(id)\",\"messages\":[],\"permissions\":[],\"truncated\":false}")
}
private func displaySnapshot() throws -> PhoneProfileSnapshot {
  let profile = exampleProfile(phase: .prepared).recording(
    pairingStatus: nil,
    nativeReceiver: "native-receiver", nativeStatus: nil, recoveredPurge: nil, retired: false)
  return try .init(registry: exampleProfiles(profile), local: nil, nativeStatus: nil, source: nil)
}
private actor DisplaySnapshots: PhoneSnapshotStoring {
  var loads = 0
  var saves = 0
  func load(_ scope: PhoneCacheScope) throws -> PhoneSnapshot? {
    loads += 1
    var value = PhoneSnapshot()
    value.list = try displayList("old-cache")
    return value
  }
  func save(_ snapshot: PhoneSnapshot, scope: PhoneCacheScope) { saves += 1 }
}
private actor DisplayGateway: MessagingRepository, ConnectionLeasing, AgentDirectory,
  ConversationFollowing
{
  var connections: [String] = []
  var lists = 0
  var reads = 0
  var sends = 0
  var creations = 0
  var offline = false
  var connectingGate: CoordinatorGate?
  func blockConnection(_ gate: CoordinatorGate) { connectingGate = gate }
  var continuation: AsyncThrowingStream<ConversationUpdate, Error>.Continuation?
  var following = false
  func setOffline() { offline = true }
  func connect(address: String, credential: String, instance: String) async throws {
    connections.append(address)
    if let connectingGate { await connectingGate.pause() }
    if offline { throw URLError(.cannotConnectToHost) }
  }
  func connectWithLease(address: String, credential: String, instance: String) async throws
    -> GatewayConnectionLease
  {
    try await connect(address: address, credential: credential, instance: instance)
    return .init()
  }
  func retire(_ lease: GatewayConnectionLease) {}
  func agents() -> [AgentProfile] { [] }
  func disconnect() {
    continuation?.finish()
    continuation = nil
  }
  func list() throws -> NessaConversationList {
    lists += 1
    return try displayList("product")
  }
  func read(_ id: String) throws -> NessaConversationView {
    reads += 1
    return try displayView(id)
  }
  func create(agent: String?, model: String?) -> String {
    creations += 1
    return "new"
  }
  func send(_ text: String, attachments: [DraftAttachment], conversationID: String) -> String {
    sends += 1
    return "turn"
  }
  func answer(_ permission: NessaPermission, option: NessaPermission.Option, conversationID: String)
  {}
  func delete(_ conversationID: String) {}
  func listArchived() -> NessaConversationList { .init(conversations: [], complete: true) }
  func setArchived(_ archived: Bool, conversationID: String) {}
  func follow(_ id: String?, after: ConversationCursor?) -> AsyncThrowingStream<
    ConversationUpdate, Error
  > {
    following = true
    let pair = AsyncThrowingStream<ConversationUpdate, Error>.makeStream()
    continuation = pair.continuation
    return pair.stream
  }
  func emit(_ id: String) throws { continuation?.yield(.list(try displayList(id))) }
}
private actor DisplaySync: PhoneSyncRunning {
  let snapshot: PhoneProfileSnapshot?
  let startupError: (any Error)?
  let startupGate: CoordinatorGate?
  var displayGate: CoordinatorGate?
  var failDisplay = false
  var returnedFailure: Int?
  var withdrawing = false
  var tombstone = false
  var unavailable: Set<String> = []
  var starts = 0
  var suspends = 0
  var requests: [[String]] = []
  init(_ snapshot: PhoneProfileSnapshot?, error: (any Error)? = nil, gate: CoordinatorGate? = nil) {
    self.snapshot = snapshot
    startupError = error
    startupGate = gate
  }
  func configure(
    gate: CoordinatorGate? = nil, failure: Bool = false, unavailable: Set<String> = [],
    returnedFailure: Int? = nil, withdraw: Bool = false, tombstone: Bool = false
  ) {
    displayGate = gate
    failDisplay = failure
    self.returnedFailure = returnedFailure
    withdrawing = withdraw
    self.tombstone = tombstone
    self.unavailable = unavailable
  }
  func startup() async throws -> PhoneSyncStartup? {
    starts += 1
    if let startupGate { await startupGate.pause() }
    if let startupError { throw startupError }
    guard let snapshot else { return nil }
    let profile = snapshot.profile
    return .init(
      snapshot: snapshot,
      connection: profile.phase == .prepared
        ? .init(
          address: profile.productAddress, credential: "fixture", instance: profile.instance) : nil)
  }
  func savedProfiles() -> PhoneProfiles? { snapshot?.registry }
  func display(on lease: GatewayConnectionLease?, conversations: [String], revision: UUID)
    async throws -> PhoneRetainedDisplay
  {
    requests.append(conversations)
    if let displayGate { await displayGate.pause() }
    if failDisplay { throw PhoneRetainedHistoryRefusal.unavailable }
    guard let snapshot else { throw PhoneSyncRuntimeRefusal.unavailable }
    let scope = RetainedScope(
      accessEpoch: "1", incarnation: "inc", origin: "origin",
      receiver: "native-receiver", schema: "1", stream: "stream")
    let page = RetainedCataloguePage(
      activeBoundary: nil, activeCursor: nil, completed: 0,
      entries: tombstone
        ? [
          .init(
            agent: nil, archived: nil, createdAtMs: 1, deleted: true,
            key: .init(creation: 1, id: "native"), model: nil, preview: nil, revision: 2,
            title: nil, updatedAtMs: nil)
        ] : [], generation: 1, next: nil, scope: scope)
    var transcripts: [String: PhoneRetainedTranscriptRead] = [:]
    for id in conversations {
      if unavailable.contains(id) || withdrawing || tombstone {
        transcripts[id] = .failed(PhoneRetainedHistoryRefusal.unavailable)
      } else {
        let projection = RetainedConversationProjection(
          json: Data(), revision: revision.uuidString,
          revisionEpoch: revision, display: try displayView(id))
        transcripts[id] = .available(
          .init(
            profileID: snapshot.profile.id,
            revision: snapshot.registry.revision,
            value: .init(
              state: .retained, scope: scope,
              downloaded: 0, applied: 0, facts: 0, generation: 1, view: .available(projection))))
      }
    }
    let successful = coordinatorStatus(coordinatorReceipt(phase: .active))
    let failedStatus = RetainedStatus(
      completionCaptured: false,
      failure: .init(
        crypto: nil, ioDiagnostic: nil, kind: .wire, storage: nil, wire: nil, worker: nil),
      purge: nil, purgeAttempted: false, purgeFailure: nil, receipt: nil)
    let refreshed = RetainedRefresh(
      initial: returnedFailure == 1 ? failedStatus : successful,
      read: .init(
        complete: returnedFailure != 4, conversations: 1,
        failure: returnedFailure == 0 ? .refused : nil, moved: false,
        withdrawn: withdrawing ? ["native"] : []),
      recheck: returnedFailure == 2 ? failedStatus : (returnedFailure == 0 ? successful : nil),
      selectionFailure: returnedFailure == 3
        ? .init(
          crypto: nil, ioDiagnostic: nil, kind: .noPending,
          storage: nil, wire: nil, worker: nil) : nil)
    let source = lease.map {
      AuthenticatedGatewaySession(
        connection: $0,
        snapshot: .init(
          identity: snapshot.profile.identity, expiresAt: nil, grants: [], methods: []))
    }
    let observed = try PhoneProfileSnapshot(
      registry: snapshot.registry, local: snapshot.local,
      nativeStatus: snapshot.nativeStatus, source: source, nativeRefresh: refreshed)
    return .init(
      snapshot: observed,
      catalogue: .init(
        profileID: snapshot.profile.id,
        revision: snapshot.registry.revision, pages: [page],
        list: (withdrawing || tombstone)
          ? try displayDecode(
            NessaConversationList.self,
            "{\"conversations\":[],\"complete\":true}") : try displayList("native")),
      transcripts: transcripts, refreshFailure: nil)
  }
  func suspend() { suspends += 1 }
  func close() {}
  func restore() -> PhoneProfileSnapshot? { snapshot }
  func prepare(_ desired: PhoneProfile, credential: String, on lease: GatewayConnectionLease) throws
    -> PhoneProfileSnapshot
  { throw PhoneSyncRuntimeRefusal.unavailable }
  func startPairing(on lease: GatewayConnectionLease) throws -> PhoneProfileSnapshot {
    throw PhoneSyncRuntimeRefusal.unavailable
  }
  func resolveInvitation(_ invitation: Data, on lease: GatewayConnectionLease) throws
    -> PhoneProfileSnapshot
  { throw PhoneSyncRuntimeRefusal.unavailable }
  func discardUnenrolled() throws -> PhoneProfileSnapshot {
    throw PhoneSyncRuntimeRefusal.unavailable
  }
  func observePairing(on lease: GatewayConnectionLease) throws -> PhoneProfileSnapshot {
    throw PhoneSyncRuntimeRefusal.unavailable
  }
  func approve(_ confirmation: PhonePairingConfirmation, on lease: GatewayConnectionLease) throws
    -> PhoneProfileSnapshot
  { throw PhoneSyncRuntimeRefusal.unavailable }
  func cancelPairing(on lease: GatewayConnectionLease) throws -> PhoneProfileSnapshot {
    throw PhoneSyncRuntimeRefusal.unavailable
  }
  func refresh(on lease: GatewayConnectionLease?) throws -> PhoneProfileSnapshot {
    throw PhoneSyncRuntimeRefusal.unavailable
  }
  func cataloguePage(after: RetainedEntryKey?, maximum: UInt32) throws -> PhoneScopedRetention<
    RetainedCataloguePage?
  > { throw PhoneSyncRuntimeRefusal.unavailable }
  func transcript(conversation: String, revision: UUID) throws -> PhoneScopedRetention<
    RetainedTranscript
  > { throw PhoneSyncRuntimeRefusal.unavailable }
}
@MainActor private func displayModel(
  _ sync: DisplaySync, _ gateway: DisplayGateway,
  _ snapshots: DisplaySnapshots
) -> MessagesViewModel {
  .init(
    service: MessagingService(repository: gateway), credentials: InMemoryCredentialStore(),
    preferences: InMemoryChatPreferences(),
    snapshots: PhoneSnapshotSession(
      store: snapshots,
      coalescingDelay: .zero), phoneSync: sync)
}

@Test @MainActor func nativeStartupOwnsColdHistoryAndOfflineTranscriptWithoutLegacyReads()
  async throws
{
  let sync = DisplaySync(try displaySnapshot())
  let gateway = DisplayGateway()
  await gateway.setOffline()
  let snapshots = DisplaySnapshots()
  let model = displayModel(sync, gateway, snapshots)
  await model.connect(
    address: "unused", credential: "", instance: "unused", restoringSavedProfile: true)
  #expect(model.conversations.map(\.id) == ["native"])
  #expect(!model.connected && model.nativeHistoryReady)
  await model.refresh("native")
  #expect(model.views["native"] != nil)
  #expect(await snapshots.loads == 0)
  #expect(await snapshots.saves == 0)
  #expect(await gateway.lists == 0)
  #expect(await gateway.reads == 0)
  #expect(await gateway.connections == [try displaySnapshot().profile.productAddress])
  #expect(!model.canSubmit(in: "native"))
  await model.suspendConnection()
}

@Test @MainActor func onlyAbsentNativeRegistryAllowsLegacyHydrationAndUnavailableDoesNotFallback()
  async throws
{
  for mode in 0..<4 {
    let registry: PhoneProfileSnapshot?
    if mode == 2 {
      registry = try .init(
        registry: exampleProfiles(exampleProfile()), local: nil, nativeStatus: nil, source: nil)
    } else if mode == 3 {
      let retired = exampleProfile(phase: .prepared).recording(
        pairingStatus: nil, nativeReceiver: nil,
        nativeStatus: nil, recoveredPurge: nil, retired: true, retirementReason: .userDiscarded)
      registry = try .init(
        registry: exampleProfiles(retired), local: nil, nativeStatus: nil, source: nil)
    } else {
      registry = nil
    }
    let sync = DisplaySync(
      registry,
      error: mode == 1
        ? PhoneProfileStoreError.corrupt
        : (mode == 2 ? PhoneProfileCoordinationRefusal.knownInvitationNeedsRecovery : nil))
    let gateway = DisplayGateway()
    let snapshots = DisplaySnapshots()
    let model = displayModel(sync, gateway, snapshots)
    await model.connect(address: "mock://legacy", credential: "fixture", instance: "phone")
    #expect(await snapshots.loads == (mode == 0 ? 1 : 0))
    #expect(await gateway.lists == (mode == 0 ? 1 : 0))
    #expect(model.conversationAuthorityReady == (mode == 0))
    if mode != 0 { #expect(model.conversations.isEmpty) }
    await model.suspendConnection()
  }
}

@Test @MainActor func nativeUnavailableAndLateProductEventsNeverReplaceRetainedRows() async throws {
  let sync = DisplaySync(try displaySnapshot())
  let gateway = DisplayGateway()
  let snapshots = DisplaySnapshots()
  let model = displayModel(sync, gateway, snapshots)
  await model.connect(address: "mock://phone", credential: "fixture", instance: "phone")
  #expect(model.connected && model.acceptedLease != nil)
  let watch = Task { await model.watchInbox() }
  for _ in 0..<2000 {
    if await gateway.following { break }
    await Task.yield()
  }
  try await gateway.emit("foreign-product")
  for _ in 0..<2000 {
    if await sync.requests.count >= 2 { break }
    await Task.yield()
  }
  #expect(model.conversations.map(\.id) == ["native"])
  #expect(await snapshots.loads == 0)
  #expect(await snapshots.saves == 0)
  await model.refresh("native")
  #expect(model.views["native"] != nil)
  await sync.configure(unavailable: ["native"])
  await model.refresh("native")
  #expect(model.views["native"] == nil)
  #expect(await gateway.reads == 0)
  await sync.configure(failure: true)
  try await gateway.emit("resurrected-product")
  for _ in 0..<2000 {
    if !model.nativeHistoryReady { break }
    await Task.yield()
  }
  #expect(model.conversations.isEmpty && !model.canSubmit(in: "native"))
  #expect(model.connected)  // Setup control plane survives unavailable history.
  watch.cancel()
  await watch.value
  await model.suspendConnection()
  #expect(model.acceptedLease == nil)
  #expect(await sync.suspends == 1)
}

@Test @MainActor func nativeDisplayCoalescesAndServicesTargetsArrivingDuringAnAdmittedRead()
  async throws
{
  let sync = DisplaySync(try displaySnapshot())
  let gateway = DisplayGateway()
  let snapshots = DisplaySnapshots()
  let model = displayModel(sync, gateway, snapshots)
  await model.connect(address: "mock://phone", credential: "fixture", instance: "phone")
  let gate = CoordinatorGate()
  await sync.configure(gate: gate)
  let first = Task { await model.refresh("one") }
  await gate.wait()
  let second = Task { await model.refresh("two") }
  await Task.yield()
  await gate.release()
  await first.value
  await second.value
  #expect(model.views["one"] != nil && model.views["two"] != nil)
  #expect(await sync.requests.suffix(2).contains(["one"]))
  #expect(await sync.requests.suffix(2).contains(["two"]))
  await model.suspendConnection()
}

@Test @MainActor func lateNativeStartupCannotReplaceNewManualConnection() async throws {
  let gate = CoordinatorGate()
  let sync = DisplaySync(try displaySnapshot(), gate: gate)
  let gateway = DisplayGateway()
  let snapshots = DisplaySnapshots()
  let model = displayModel(sync, gateway, snapshots)
  let automatic = Task {
    await model.connect(
      address: "old", credential: "", instance: "old", restoringSavedProfile: true)
  }
  await gate.wait()
  let manual = Task { await model.connect(address: "new", credential: "new", instance: "new") }
  await Task.yield()
  await gate.release()
  await automatic.value
  await manual.value
  #expect(await gateway.connections == ["new"])
  #expect(model.connected)
  #expect(await snapshots.loads == 0)
  await model.suspendConnection()
}

@Test @MainActor func pairedCommandRechecksNativeInsteadOfTrustingEarlierReadyDisplay() async throws
{
  let sync = DisplaySync(try displaySnapshot())
  let gateway = DisplayGateway()
  let snapshots = DisplaySnapshots()
  let model = displayModel(sync, gateway, snapshots)
  await model.connect(address: "mock://phone", credential: "fixture", instance: "phone")
  await model.refresh("native")
  #expect(model.canSubmit(in: "native"))
  await sync.configure(failure: true)
  #expect(model.nativeHistoryReady)
  #expect(!(await model.send("Do not dispatch after native refusal", to: "native")))
  #expect(await gateway.sends == 0)
  #expect(await gateway.creations == 0)
  #expect(await model.create() == nil)
  await model.suspendConnection()
}

@Test @MainActor func foregroundRestoresNativeAfterBackgroundBeforeRedial() async throws {
  let sync = DisplaySync(try displaySnapshot())
  let gateway = DisplayGateway()
  let snapshots = DisplaySnapshots()
  let model = MessagesViewModel(
    service: MessagingService(repository: gateway),
    credentials: InMemoryCredentialStore(), preferences: InMemoryChatPreferences(),
    snapshots: PhoneSnapshotSession(store: snapshots, coalescingDelay: .zero),
    recovery: ConnectionRecovery(waiting: SystemRecoveryWait()), phoneSync: sync)
  await model.connect(
    address: "unused", credential: "", instance: "unused", restoringSavedProfile: true)
  let firstLease = try #require(model.acceptedLease)
  await model.suspendConnection()
  #expect(model.acceptedLease == nil && !model.connected)
  model.resumeConnection()
  for _ in 0..<4000 {
    if model.connected { break }
    await Task.yield()
  }
  #expect(model.connected && model.acceptedLease != firstLease)
  #expect(await sync.starts == 2)
  #expect(await snapshots.loads == 0)
  await model.suspendConnection()
}

@Test @MainActor func manualConnectionCannotDisplayOldNativeHistoryBeforeReadyIdentity()
  async throws
{
  let sync = DisplaySync(try displaySnapshot())
  let gateway = DisplayGateway()
  let gate = CoordinatorGate()
  await gateway.blockConnection(gate)
  let snapshots = DisplaySnapshots()
  let model = displayModel(sync, gateway, snapshots)
  let connecting = Task {
    await model.connect(address: "new-account", credential: "other", instance: "other")
  }
  await gate.wait()
  #expect(model.conversations.isEmpty && model.views.isEmpty)
  #expect(await sync.requests.isEmpty)
  #expect(await snapshots.loads == 0)
  await gate.release()
  await connecting.value
  await model.suspendConnection()
}

@Test @MainActor func returnedNativeFailureKeepsCachedHistoryButCannotAuthorizeCommands()
  async throws
{
  for failure in 0..<4 {
    let sync = DisplaySync(try displaySnapshot())
    let gateway = DisplayGateway()
    let snapshots = DisplaySnapshots()
    let model = displayModel(sync, gateway, snapshots)
    await model.connect(address: "mock://phone", credential: "fixture", instance: "phone")
    await model.refresh("native")
    #expect(model.canSubmit(in: "native"))
    #expect(model.phoneProfile?.nativeRefresh?.recheck == nil)
    await sync.configure(returnedFailure: failure)
    #expect(!(await model.send("Do not dispatch", to: "native")))
    #expect(await gateway.sends == 0)
    #expect(model.nativeHistoryReady && !model.nativeCommandReady)
    #expect(model.views["native"] != nil && model.connected)
    #expect(await model.create() == nil)
    #expect(await gateway.creations == 0)
    #expect(model.phoneProfile?.nativeRefresh != nil)
    await model.suspendConnection()
  }
}

@Test @MainActor func positivePartialNativeReadAllowsCommandsWithoutClaimingCatchUp() async throws {
  let sync = DisplaySync(try displaySnapshot())
  await sync.configure(returnedFailure: 4)
  let gateway = DisplayGateway()
  let model = displayModel(sync, gateway, DisplaySnapshots())
  await model.connect(address: "mock://phone", credential: "fixture", instance: "phone")
  await model.refresh("native")
  #expect(model.nativeHistoryReady && model.nativeCommandReady)
  #expect(model.phoneProfile?.nativeRefresh?.read?.complete == false)
  #expect(model.phoneProfile?.nativeRefresh?.recheck == nil)
  await model.suspendConnection()
}

@Test @MainActor func nativeAccessWithdrawalCanRegrantWithoutBecomingADeletionFence() async throws {
  let sync = DisplaySync(try displaySnapshot())
  let gateway = DisplayGateway()
  let model = displayModel(sync, gateway, DisplaySnapshots())
  await model.connect(address: "mock://phone", credential: "fixture", instance: "phone")
  await model.refresh("native")
  model.togglePin("native")
  model.react("💗", message: "turn", in: "native")
  await sync.configure(withdraw: true)
  try await model.refreshList()
  #expect(model.conversations.isEmpty && model.views["native"] == nil)
  #expect(model.isPinned("native"))
  #expect(model.reaction(message: "turn", in: "native") == "💗")
  await sync.configure()
  await model.refresh("native")
  #expect(model.conversations.map(\.id) == ["native"] && model.views["native"] != nil)
  #expect(model.isPinned("native"))
  await sync.configure(tombstone: true)
  try await model.refreshList()
  #expect(model.conversations.isEmpty && model.views["native"] == nil)
  #expect(!model.isPinned("native"))
  await sync.configure()
  try await model.refreshList()
  await model.refresh("native")
  #expect(model.conversations.isEmpty && model.views["native"] == nil)
  await model.suspendConnection()
}
