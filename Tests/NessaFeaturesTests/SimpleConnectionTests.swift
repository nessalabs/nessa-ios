import Foundation
import NessaFeatures
import Testing

private func simpleDecode<Value: Decodable>(_ type: Value.Type, _ json: String) throws -> Value {
  try JSONDecoder().decode(type, from: Data(json.utf8))
}
private func simpleList(_ id: String) throws -> NessaConversationList {
  try simpleDecode(
    NessaConversationList.self,
    "{\"conversations\":[{\"conversationId\":\"\(id)\",\"updatedAtMs\":1,\"running\":false}],\"complete\":true}"
  )
}
private func simpleView(_ id: String) throws -> NessaConversationView {
  try simpleDecode(
    NessaConversationView.self,
    "{\"conversationId\":\"\(id)\",\"messages\":[],\"permissions\":[],\"truncated\":false}")
}

@Test @MainActor func simpleSavedEndpointMatchesActualReconnectAfterFailedReplacement() async {
  let gateway = SimpleGateway()
  let model = MessagesViewModel(
    service: MessagingService(repository: gateway),
    credentials: InMemoryCredentialStore(), preferences: InMemoryChatPreferences())
  await model.connect(address: "original", credential: "original-secret", instance: "original")
  #expect(model.connected)
  await gateway.setOffline()
  await model.connect(address: "failed", credential: "failed-secret", instance: "failed")
  #expect(!model.connected && model.currentGatewayAddress == "failed")
  #expect(model.hasSavedConnection && model.savedReconnectGatewayAddress == "original")
  await gateway.setOnline()
  await model.reconnectSavedConnection()
  #expect(model.connected && model.currentGatewayAddress == "original")
  #expect(await gateway.connections == ["original", "failed", "original"])
  await model.suspendConnection()
}
private func simpleSnapshot() throws -> PhoneProfileSnapshot {
  let profile = exampleProfile(phase: .prepared).recording(
    pairingStatus: nil,
    nativeReceiver: "native-receiver", nativeStatus: nil, recoveredPurge: nil, retired: false)
  return try .init(registry: exampleProfiles(profile), local: nil, nativeStatus: nil, source: nil)
}
private actor SimpleSnapshots: PhoneSnapshotStoring {
  var loads = 0
  var saves = 0
  var scopes: [PhoneCacheScope] = []
  func load(_ scope: PhoneCacheScope) throws -> PhoneSnapshot? {
    loads += 1
    scopes.append(scope)
    var value = PhoneSnapshot()
    value.list = try simpleList("old-cache")
    value.views["old-cache"] = try simpleView("old-cache")
    value.recentViews = ["old-cache"]
    return value
  }
  func save(_ snapshot: PhoneSnapshot, scope: PhoneCacheScope) { saves += 1 }
}
private actor SimpleGateway: MessagingRepository, ConnectionLeasing, AgentDirectory,
  ConversationFollowing
{
  var connections: [String] = []
  var lists = 0
  var reads = 0
  var sends = 0
  var creations = 0
  var retired: [GatewayConnectionLease] = []
  var retirementGate: CoordinatorGate?
  var deletions = 0
  var offline = false
  var connectingGate: CoordinatorGate?
  func blockConnection(_ gate: CoordinatorGate) { connectingGate = gate }
  var continuation: AsyncThrowingStream<ConversationUpdate, Error>.Continuation?
  var following = false
  func setOffline() { offline = true }
  func setOnline() { offline = false }
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
  func retire(_ lease: GatewayConnectionLease) async {
    retired.append(lease)
    if let retirementGate { await retirementGate.pause() }
  }
  func holdRetirement(_ gate: CoordinatorGate) { retirementGate = gate }
  func agents() -> [AgentProfile] { [] }
  func disconnect() {
    continuation?.finish()
    continuation = nil
  }
  func list() throws -> NessaConversationList {
    lists += 1
    return try simpleList("product")
  }
  func read(_ id: String) throws -> NessaConversationView {
    reads += 1
    return try simpleView(id)
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
  func delete(_ conversationID: String) { deletions += 1 }
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
  func emit(_ id: String) throws { continuation?.yield(.list(try simpleList(id))) }
}
private actor SimpleSync: PhoneSyncRunning {
  var snapshot: PhoneProfileSnapshot?
  var startupError: (any Error)?
  let startupGate: CoordinatorGate?
  var simpleGate: CoordinatorGate?
  var failSimple = false
  var returnedFailure: Int?
  var withdrawing = false
  var tombstone = false
  var unavailable: Set<String> = []
  var starts = 0
  var passiveStarts = 0
  var passiveReads = 0
  var passiveGate: CoordinatorGate?
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
    simpleGate = gate
    failSimple = failure
    self.returnedFailure = returnedFailure
    withdrawing = withdraw
    self.tombstone = tombstone
    self.unavailable = unavailable
  }
  func failStartup(_ failure: any Error) { startupError = failure }
  func replaceSnapshot(_ snapshot: PhoneProfileSnapshot?) { self.snapshot = snapshot }
  func holdPassive(_ gate: CoordinatorGate) { passiveGate = gate }
  func passiveStartup() throws -> PhoneSyncStartup? {
    passiveStarts += 1
    if let startupError { throw startupError }
    guard let snapshot else { return nil }
    return .init(
      snapshot: snapshot,
      connection: snapshot.profile.phase == .prepared && !snapshot.profile.hasRetirementEvidence
        ? .init(
          address: snapshot.profile.productAddress, credential: "fixture",
          instance: snapshot.profile.instance) : nil)
  }
  func passiveDisplay(conversations: [String], revision: UUID) async throws -> PhoneRetainedDisplay
  {
    passiveReads += 1
    if let passiveGate { await passiveGate.pause() }
    let result = try await display(on: nil, conversations: conversations, revision: revision)
    return .init(
      snapshot: snapshot!, catalogue: result.catalogue,
      transcripts: result.transcripts, refreshFailure: nil)
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
    if let simpleGate { await simpleGate.pause() }
    if failSimple { throw PhoneRetainedHistoryRefusal.unavailable }
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
            title: nil, updatedAtMs: nil),
          .init(
            agent: nil, archived: nil, createdAtMs: 2, deleted: true,
            key: .init(creation: 2, id: "second"), model: nil, preview: nil, revision: 2,
            title: nil, updatedAtMs: nil),
        ] : [], generation: 1, next: nil, scope: scope)
    var transcripts: [String: PhoneRetainedTranscriptRead] = [:]
    for id in conversations {
      if unavailable.contains(id) || withdrawing || tombstone {
        transcripts[id] = .failed(PhoneRetainedHistoryRefusal.unavailable)
      } else {
        let projection = RetainedConversationProjection(
          json: Data(), revision: revision.uuidString,
          revisionEpoch: revision, display: try simpleView(id))
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
          ? try simpleDecode(
            NessaConversationList.self,
            "{\"conversations\":[],\"complete\":true}") : try simpleList("native")),
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
@MainActor private func simpleModel(
  _ sync: SimpleSync, _ gateway: SimpleGateway,
  _ snapshots: SimpleSnapshots
) -> MessagesViewModel {
  .init(
    service: MessagingService(repository: gateway), credentials: InMemoryCredentialStore(),
    preferences: InMemoryChatPreferences(),
    snapshots: PhoneSnapshotSession(
      store: snapshots,
      coalescingDelay: .zero), phoneSync: sync)
}

@Test @MainActor func simpleDisconnectPersistsOffAndDrainsOriginalLeaseDespiteCancelledWaiter()
  async throws
{
  let sync = SimpleSync(try simpleSnapshot())
  let gateway = SimpleGateway()
  let prefs = InMemoryChatPreferences()
  let model = MessagesViewModel(
    service: MessagingService(repository: gateway),
    credentials: InMemoryCredentialStore(), preferences: prefs, phoneSync: sync)
  await model.connect(address: "original", credential: "secret", instance: "original-instance")
  await model.refresh("native")
  let lease = try #require(model.acceptedLease)
  let gate = CoordinatorGate()
  await gateway.holdRetirement(gate)
  let disconnect = Task { await model.manualDisconnect() }
  await gate.wait()
  disconnect.cancel()
  #expect(!model.connected && !model.automaticConnectionEnabled && model.acceptedLease == nil)
  #expect(model.views["native"] != nil && !model.canSubmit(in: "native"))
  #expect(prefs.strings(forKey: "nessa.connection.automatic") == ["disabled"])
  #expect(prefs.mapping(forKey: "nessa.connection.saved") == nil)
  #expect(await gateway.retired == [lease])
  let connecting = Task { await model.reconnectSavedConnection() }
  for _ in 0..<30 { await Task.yield() }
  #expect(await gateway.connections.count == 1)
  await gate.release()
  await disconnect.value
  await connecting.value
  #expect(model.connected && model.automaticConnectionEnabled)
  #expect(await gateway.connections == ["original", "original"])
  await model.suspendConnection()
}

@Test @MainActor func simpleColdOffRestoreUsesSavedNativeTupleAndZeroProductContact() async throws {
  let sync = SimpleSync(try simpleSnapshot())
  let gateway = SimpleGateway()
  let prefs = InMemoryChatPreferences()
  prefs.save(["disabled"], forKey: "nessa.connection.automatic")
  let model = MessagesViewModel(
    service: MessagingService(repository: gateway),
    credentials: InMemoryCredentialStore(), preferences: prefs, phoneSync: sync)
  await model.connect(
    address: "foreign-launch", credential: "foreign-secret", instance: "foreign",
    automatically: true)
  #expect(!model.connected && model.hasSavedConnection && model.nativeHistoryReady)
  #expect(!model.nativeCommandReady && !model.canSubmit(in: "native"))
  #expect(model.conversations.map(\.id) == ["native"])
  await model.refresh("native")
  try await model.refreshList()
  if !model.connected {
    await model.watchInbox()
    await model.watchConversation("native")
  }
  #expect(model.views["native"] != nil)
  #expect(await sync.starts == 0)
  #expect(await sync.passiveStarts == 1)
  #expect(await gateway.connections.isEmpty)
  #expect(await gateway.lists == 0)
  #expect(await gateway.reads == 0)
  #expect(await gateway.sends == 0)
  model.resumeConnection()
  for _ in 0..<30 { await Task.yield() }
  #expect(await gateway.connections.isEmpty)
  await model.reconnectSavedConnection()
  #expect(await gateway.connections == [try simpleSnapshot().profile.productAddress])
  #expect(model.connected && model.automaticConnectionEnabled)
  await model.suspendConnection()
}

@Test @MainActor func simpleHeldPassiveReadCannotPublishAfterBackgroundAndDrainsBeforeReplacement()
  async throws
{
  let sync = SimpleSync(try simpleSnapshot())
  let gateway = SimpleGateway()
  let prefs = InMemoryChatPreferences()
  prefs.save(["disabled"], forKey: "nessa.connection.automatic")
  let model = MessagesViewModel(
    service: MessagingService(repository: gateway),
    credentials: InMemoryCredentialStore(), preferences: prefs, phoneSync: sync)
  await model.connect(address: "unused", credential: "", instance: "unused", automatically: true)
  let gate = CoordinatorGate()
  await sync.holdPassive(gate)
  let read = Task { await model.refresh("late") }
  await gate.wait()
  read.cancel()
  let suspend = Task { await model.suspendConnection() }
  for _ in 0..<30 { await Task.yield() }
  let replacement = Task { await model.connect(address: "new", credential: "new", instance: "new") }
  for _ in 0..<30 { await Task.yield() }
  #expect(await gateway.connections.isEmpty)
  await gate.release()
  await read.value
  await suspend.value
  await replacement.value
  #expect(model.views["late"] == nil && !model.connected)
  model.resumeConnection()
  await model.connect(address: "new", credential: "new", instance: "new")
  #expect(await gateway.connections == ["new"])
  await model.suspendConnection()
}

@Test func simpleActualPassiveRuntimeNeverCallsNativeStatusRefreshOrRepairsRegistry() async throws {
  let profile = exampleProfile(phase: .prepared).recording(
    pairingStatus: nil,
    nativeReceiver: "native-receiver",
    nativeStatus: coordinatorStatus(coordinatorReceipt(phase: .active)),
    recoveredPurge: nil, retired: false)
  let harness = CoordinatorHarness(profile: profile, local: coordinatorLocal(issued: true))
  let runtime = PhoneSyncRuntime(
    profiles: harness.profiles, credentials: harness.credentials,
    factory: { harness.coordinator() })
  let restored = try #require(try await runtime.passiveStartup())
  #expect(restored.connection?.credential == "fixture")
  #expect(restored.snapshot.source == nil && restored.snapshot.nativeRefresh == nil)
  do { _ = try await runtime.passiveDisplay(conversations: ["cached"], revision: UUID()) } catch let
    failure as PhoneSyncRuntimeFailure
  {
    #expect(failure.underlying is PhoneProfileCoordinationFailure)
  }
  #expect(await harness.native.statuses == 0)
  #expect(await harness.native.refreshes == 0)
  #expect(await harness.native.reads == 1)
  #expect(await harness.profiles.writes == 0)
  #expect(await harness.gateway.creates == 0)
  #expect(await harness.gateway.approvals == 0)
  #expect(await harness.withdrawal.scopes.isEmpty)
  try await runtime.suspend()
}

private actor SimpleNativeCache: RetainedSession {
  var local: RetainedLocalEnrollment? = coordinatorLocal(issued: true)
  var statusCalls = 0
  var refreshCalls = 0
  var pages = 0
  var transcripts = 0
  var closes = 0
  var foreign = false
  var purge: RetainedPurge?
  let scope = RetainedScope(
    accessEpoch: "99", incarnation: "inc", origin: "origin",
    receiver: "native-receiver", schema: "1", stream: "stream")
  func configure(foreign: Bool = false, missing: Bool = false, purged: Bool = false) {
    self.foreign = foreign
    local = coordinatorLocal(issued: !missing)
    if purged {
      local = nil
      purge = .init(
        catalogueEntries: 2, observedAtMs: 300,
        receiver: "native-receiver", records: 1, transcripts: 1)
    }
  }
  func localEnrollment() -> RetainedLocalEnrollment? { local }
  func enroll(code: String) throws -> RetainedEnrollmentReceipt {
    throw RetainedSessionError.invalidArgument
  }
  func retry(code: String) throws -> RetainedRetry { throw RetainedSessionError.invalidArgument }
  func status() throws -> RetainedStatus {
    statusCalls += 1
    throw RetainedSessionError.invalidArgument
  }
  func refresh() throws -> RetainedRefresh {
    refreshCalls += 1
    throw RetainedSessionError.invalidArgument
  }
  func cataloguePage(after: RetainedEntryKey?, maximum: UInt32) -> RetainedCataloguePage? {
    pages += 1
    return .init(
      activeBoundary: nil, activeCursor: nil, completed: 0,
      entries: [
        .init(
          agent: nil, archived: nil, createdAtMs: 1, deleted: false,
          key: .init(creation: 1, id: "cached"), model: nil, preview: nil, revision: 1,
          title: nil, updatedAtMs: nil)
      ], generation: 9, next: nil, scope: scope)
  }
  func transcript(conversation: String, revision: UUID) throws -> RetainedTranscript {
    transcripts += 1
    let selected = RetainedScope(
      accessEpoch: scope.accessEpoch, incarnation: "conversation-inc",
      origin: foreign ? "foreign-origin" : scope.origin, receiver: scope.receiver,
      schema: "conversation-schema", stream: "conversation-stream")
    return .init(
      state: .retained, scope: selected, downloaded: 0, applied: 0, facts: 0,
      generation: 37,
      view: .available(
        .init(
          json: Data(), revision: revision.uuidString,
          revisionEpoch: revision, display: try simpleView(conversation))))
  }
  func purgeReceipt(receiver: String) -> RetainedPurge? { purge }
  func close() { closes += 1 }
}

@Test func simpleActualPassiveCacheReturnsHistoricalProjectionAndRejectsForeignScope() async throws
{
  for foreign in [false, true] {
    let profile = exampleProfile(phase: .prepared).recording(
      pairingStatus: nil,
      nativeReceiver: "native-receiver",
      nativeStatus: coordinatorStatus(coordinatorReceipt(phase: .active)),
      recoveredPurge: nil, retired: false)
    let harness = CoordinatorHarness(profile: profile)
    let native = SimpleNativeCache()
    await native.configure(foreign: foreign)
    let factory = CoordinatorFactory(native)
    let runtime = PhoneSyncRuntime(
      profiles: harness.profiles, credentials: harness.credentials,
      factory: {
        PhoneProfileCoordinator(
          profiles: harness.profiles, credentials: harness.credentials,
          locations: CoordinatorLocations(), identity: harness.gateway, pairing: harness.gateway,
          factory: factory, withdrawal: harness.withdrawal)
      })
    _ = try await runtime.passiveStartup()
    let display = try await runtime.passiveDisplay(conversations: ["cached"], revision: UUID())
    #expect(display.snapshot.source == nil && display.snapshot.nativeRefresh == nil)
    #expect(display.catalogue.list.conversations.map(\.id) == ["cached"])
    let transcript = try #require(display.transcripts["cached"])
    if foreign {
      guard case .failed(let error) = transcript else {
        Issue.record("Foreign cache accepted")
        continue
      }
      let evidence = try #require(error as? PhoneRetainedHistoryFailure)
      #expect(evidence.underlying as? PhoneRetainedHistoryRefusal == .changed)
      #expect(evidence.transcript?.scope?.origin == "foreign-origin")
      #expect(evidence.pages.first?.scope.incarnation == "inc")
    } else {
      guard case .available(let value) = transcript else {
        Issue.record("Cached projection refused")
        continue
      }
      #expect(value.value.scope?.incarnation == "conversation-inc")
      #expect(value.value.scope?.schema == "conversation-schema")
      #expect(value.value.scope?.stream == "conversation-stream")
      #expect(value.value.generation == 37)
    }
    #expect(await native.statusCalls == 0)
    #expect(await native.refreshCalls == 0)
    #expect(await native.pages == 1)
    #expect(await native.transcripts == 1)
    #expect(await harness.profiles.writes == 0)
    try await runtime.suspend()
  }
}

@Test func simplePassiveMissingIssuedOrPurgeCannotInventReadinessAndRetainsPurgeEvidence()
  async throws
{
  for purged in [false, true] {
    let profile = exampleProfile(phase: .prepared).recording(
      pairingStatus: nil,
      nativeReceiver: "native-receiver", nativeStatus: nil, recoveredPurge: nil, retired: false)
    let harness = CoordinatorHarness(profile: profile)
    let native = SimpleNativeCache()
    await native.configure(missing: !purged, purged: purged)
    let factory = CoordinatorFactory(native)
    let runtime = PhoneSyncRuntime(
      profiles: harness.profiles, credentials: harness.credentials,
      factory: {
        PhoneProfileCoordinator(
          profiles: harness.profiles, credentials: harness.credentials,
          locations: CoordinatorLocations(), identity: harness.gateway, pairing: harness.gateway,
          factory: factory, withdrawal: harness.withdrawal)
      })
    do {
      _ = try await runtime.passiveStartup()
      Issue.record("Missing or purged enrollment accepted")
    } catch let error as PhoneSyncRuntimeFailure {
      let underlying = try #require(error.underlying as? PhoneProfileCoordinationFailure)
      if purged {
        let evidence = try #require(underlying.underlying as? PhonePassivePurgeFailure)
        #expect(evidence.profileID == profile.id && evidence.receipt.records == 1)
      } else {
        #expect(underlying.underlying as? PhoneProfileCoordinationRefusal == .receiverUnavailable)
      }
    }
    #expect(await native.statusCalls == 0)
    #expect(await native.refreshCalls == 0)
    #expect(await native.pages == 0)
    #expect(await harness.profiles.writes == 0)
    #expect(await harness.withdrawal.scopes.isEmpty)
    try await runtime.suspend()
  }
}

private final class SimpleCredentials: NessaCredentialStoring, @unchecked Sendable {
  private let lock = NSLock()
  private var value: String?
  func load() -> String? { lock.withLock { value } }
  func save(_ credential: String) { lock.withLock { value = credential } }
}

@Test @MainActor func simpleLegacyColdOffUsesOnlyOriginalCredentialCacheAndNeverAutomaticAuthority()
  async throws
{
  let gateway = SimpleGateway()
  let prefs = InMemoryChatPreferences()
  let credentials = SimpleCredentials()
  let snapshots = SimpleSnapshots()
  let original = MessagesViewModel(
    service: MessagingService(repository: gateway),
    credentials: credentials, preferences: prefs,
    snapshots: PhoneSnapshotSession(store: snapshots, coalescingDelay: .zero))
  await original.connect(
    address: "original-address", credential: "original-secret", instance: "original-instance")
  await original.manualDisconnect()
  let recreatedGateway = SimpleGateway()
  let recreated = MessagesViewModel(
    service: MessagingService(repository: recreatedGateway),
    credentials: credentials, preferences: prefs,
    snapshots: PhoneSnapshotSession(store: snapshots, coalescingDelay: .zero))
  await recreated.connect(
    address: "foreign-launch", credential: "foreign-secret", instance: "foreign-instance",
    automatically: true)
  #expect(recreated.visibleConversations.map(\.id) == ["old-cache"])
  #expect(recreated.views["old-cache"] != nil)
  #expect(!recreated.connected && !recreated.canSubmit(in: "old-cache"))
  #expect(
    await snapshots.scopes.last
      == PhoneCacheScope(
        address: "original-address",
        credential: "original-secret", instance: "original-instance"))
  try await recreated.refreshList()
  await recreated.refresh("old-cache")
  await recreated.watchConversation("old-cache")
  recreated.resumeConnection()
  #expect(await recreatedGateway.connections.isEmpty)
  #expect(await recreatedGateway.reads == 0)
  #expect(await recreatedGateway.lists == 0)
  await recreated.reconnectSavedConnection()
  #expect(await recreatedGateway.connections == ["original-address"])
  #expect(recreated.connected && recreated.automaticConnectionEnabled)
  await recreated.suspendConnection()
}

@Test @MainActor func simplePassiveTombstonesRemoveOnlyCurrentNativePreferences() async throws {
  let sync = SimpleSync(try simpleSnapshot())
  let gateway = SimpleGateway()
  let prefs = InMemoryChatPreferences()
  prefs.save(["disabled"], forKey: "nessa.connection.automatic")
  let model = MessagesViewModel(
    service: MessagingService(repository: gateway),
    credentials: InMemoryCredentialStore(), preferences: prefs, phoneSync: sync)
  await model.connect(
    address: "foreign", credential: "foreign", instance: "foreign", automatically: true)
  await model.refresh("native")
  await model.refresh("second")
  model.togglePin("native")
  model.togglePin("second")
  model.react("💗", message: "turn", in: "native")
  model.react("💗", message: "turn", in: "second")
  await sync.configure(tombstone: true)
  try await model.refreshList()
  #expect(model.views["native"] == nil && model.views["second"] == nil)
  #expect(!model.isPinned("native") && !model.isPinned("second"))
  #expect(model.reaction(message: "turn", in: "native") == nil)
  #expect(model.reaction(message: "turn", in: "second") == nil)
  #expect(await gateway.deletions == 0)
  #expect(await gateway.connections.isEmpty)
  await model.suspendConnection()
}

@Test @MainActor func simplePassiveCorruptionCannotFallbackToLegacyCachedRows() async throws {
  let sync = SimpleSync(try simpleSnapshot(), error: PhoneProfileStoreError.corrupt)
  let gateway = SimpleGateway()
  let snapshots = SimpleSnapshots()
  let prefs = InMemoryChatPreferences()
  prefs.save(["disabled"], forKey: "nessa.connection.automatic")
  let model = MessagesViewModel(
    service: MessagingService(repository: gateway),
    credentials: InMemoryCredentialStore(), preferences: prefs,
    snapshots: PhoneSnapshotSession(store: snapshots, coalescingDelay: .zero), phoneSync: sync)
  await model.connect(
    address: "foreign", credential: "foreign", instance: "foreign", automatically: true)
  #expect(model.phoneSyncFailure as? PhoneProfileStoreError == .corrupt)
  #expect(!model.nativeHistoryReady && !model.nativeCommandReady && !model.connected)
  #expect(model.visibleConversations.isEmpty)
  #expect(await snapshots.loads == 0)
  #expect(await gateway.connections.isEmpty)
  #expect(await sync.starts == 0)
  await model.suspendConnection()
}

@Test(arguments: [false, true]) @MainActor
func simplePassiveProtectedReplacementClearsOriginalDisplayBeforeHeldFailure(changedTuple: Bool)
  async throws
{
  let first = try simpleSnapshot()
  let next = try simpleSnapshot().profile
  let secondProfile = PhoneProfile(
    id: next.id, phase: next.phase,
    productAddress: changedTuple ? "ws://different-owner/session" : next.productAddress,
    instance: next.instance, nativeAddress: next.nativeAddress, identity: next.identity,
    nativeReceiver: next.nativeReceiver)
  let second = try PhoneProfileSnapshot(
    registry: exampleProfiles(secondProfile), local: nil,
    nativeStatus: nil, source: nil)
  let sync = SimpleSync(first)
  let gateway = SimpleGateway()
  let prefs = InMemoryChatPreferences()
  prefs.save(["disabled"], forKey: "nessa.connection.automatic")
  let model = MessagesViewModel(
    service: MessagingService(repository: gateway),
    credentials: InMemoryCredentialStore(), preferences: prefs, phoneSync: sync)
  await model.connect(address: "unused", credential: "", instance: "unused", automatically: true)
  await model.refresh("native")
  model.togglePin("native")
  model.react("💗", message: "turn", in: "native")
  #expect(model.views["native"] != nil)
  await model.manualDisconnect()
  let previousScope = model.deliveryScopeRevision
  await sync.replaceSnapshot(second)
  let gate = CoordinatorGate()
  await sync.holdPassive(gate)
  await sync.configure(failure: true)
  let replacing = Task { await model.refresh("native") }
  await gate.wait()
  #expect(model.phoneProfile?.profile.id == second.profile.id)
  #expect(model.deliveryScopeRevision > previousScope)
  #expect(model.views.isEmpty && model.visibleConversations.isEmpty)
  if changedTuple {
    #expect(!model.isPinned("native"))
    #expect(model.reaction(message: "turn", in: "native") == nil)
  }
  #expect(!model.canSubmit(in: "native") && !model.nativeCommandReady)
  await gate.release()
  await replacing.value
  #expect(model.views.isEmpty && model.visibleConversations.isEmpty)
  #expect(model.phoneSyncFailure != nil)
  #expect(await gateway.connections.isEmpty)
  await model.suspendConnection()
}

@Test(arguments: [false, true]) @MainActor
func simplePassiveTerminalOrAbsentRegistryClearsPriorDisplayWithoutLiveAuthority(absent: Bool)
  async throws
{
  let first = try simpleSnapshot()
  let sync = SimpleSync(first)
  let gateway = SimpleGateway()
  let prefs = InMemoryChatPreferences()
  prefs.save(["disabled"], forKey: "nessa.connection.automatic")
  let model = MessagesViewModel(
    service: MessagingService(repository: gateway),
    credentials: InMemoryCredentialStore(), preferences: prefs, phoneSync: sync)
  await model.connect(address: "unused", credential: "", instance: "unused", automatically: true)
  await model.refresh("native")
  #expect(model.views["native"] != nil)
  await model.manualDisconnect()
  let priorScope = model.deliveryScopeRevision
  let retired = first.profile.recording(
    pairingStatus: nil, nativeReceiver: first.profile.nativeReceiver,
    nativeStatus: coordinatorStatus(coordinatorReceipt(phase: .terminal)), recoveredPurge: nil,
    retired: true)
  let terminal = try PhoneProfileSnapshot(
    registry: exampleProfiles(retired), local: nil,
    nativeStatus: nil, source: nil)
  await sync.replaceSnapshot(absent ? nil : terminal)
  await model.connect(
    address: "foreign", credential: "foreign", instance: "foreign", automatically: true)
  #expect(model.deliveryScopeRevision > priorScope)
  #expect(model.views.isEmpty && model.visibleConversations.isEmpty)
  #expect(!model.connected && !model.canSubmit(in: "native") && !model.nativeCommandReady)
  #expect(await gateway.connections.isEmpty)
  #expect(await sync.starts == 0)
  await model.suspendConnection()
}

@Test @MainActor func simplePassiveFailedStartupFencesReplacementRecoveryMetadata() async throws {
  let first = try simpleSnapshot()
  let second = try simpleSnapshot()
  let sync = SimpleSync(first)
  let gateway = SimpleGateway()
  let prefs = InMemoryChatPreferences()
  prefs.save(["disabled"], forKey: "nessa.connection.automatic")
  let model = MessagesViewModel(
    service: MessagingService(repository: gateway),
    credentials: InMemoryCredentialStore(), preferences: prefs, phoneSync: sync)
  await model.connect(address: "unused", credential: "", instance: "unused", automatically: true)
  await model.refresh("native")
  await model.manualDisconnect()
  #expect(model.views["native"] != nil)
  let priorScope = model.deliveryScopeRevision
  await sync.replaceSnapshot(second)
  await sync.failStartup(PhoneProfileStoreError.corrupt)
  await model.connect(
    address: "foreign", credential: "foreign", instance: "foreign", automatically: true)
  #expect(model.phoneProfile?.profile.id == second.profile.id)
  #expect(model.deliveryScopeRevision > priorScope)
  #expect(model.views.isEmpty && model.visibleConversations.isEmpty)
  #expect(model.phoneSyncFailure as? PhoneProfileStoreError == .corrupt)
  #expect(!model.nativeCommandReady && !model.nativeHistoryReady && !model.connected)
  #expect(await gateway.connections.isEmpty)
  #expect(await sync.starts == 0)
  await model.suspendConnection()
}
