import Foundation
import Testing

@testable import NessaFeatures

private actor RecordingWait: RecoveryWaiting {
  var delays: [Duration] = []
  func wait(for duration: Duration) async throws {
    delays.append(duration)
    try Task.checkCancellation()
  }
}
private actor Attempts {
  var count = 0
  func run(failures: Int, error: NessaGatewayError = .disconnected) throws {
    count += 1
    if count <= failures { throw error }
  }
}
@Test func recoveryBacksOffToBoundAndRefusalsDoNotRetry() async throws {
  let clock = RecordingWait()
  let attempts = Attempts()
  try await ConnectionRecovery(waiting: clock).run { try await attempts.run(failures: 8) }
  #expect(
    await clock.delays
      == [500, 1000, 2000, 4000, 8000, 15000, 15000, 15000].map { .milliseconds($0) })
  let refused = Attempts()
  let noWait = RecordingWait()
  await #expect(throws: NessaGatewayError.self) {
    try await ConnectionRecovery(waiting: noWait).run {
      try await refused.run(failures: 10, error: .rejected("Authority refused"))
    }
  }
  #expect(await refused.count == 1)
  #expect(await noWait.delays.isEmpty)
  #expect(!ConnectionRecovery.retryable(URLError(.serverCertificateUntrusted)))
}
@Test func cancellationDuringRecoveryDelayPreventsAnotherDial() async {
  let attempts = Attempts()
  let task = Task {
    try await ConnectionRecovery(waiting: SystemRecoveryWait()).run {
      try await attempts.run(failures: 100)
    }
  }
  for _ in 0..<2000 {
    if await attempts.count == 1 { break }
    await Task.yield()
  }
  task.cancel()
  await #expect(throws: CancellationError.self) { try await task.value }
  #expect(await attempts.count == 1)
}
private actor SwitchingGateway: MessagingRepository, AgentDirectory, ConversationFollowing {
  let base = MockRepository()
  var online = true
  var connections: [String] = []
  var sends = 0
  var disconnects = 0
  private var configuredAgents: [AgentProfile]?
  private var blockList = false
  private var listGate: CheckedContinuation<Void, Never>?
  var listing = false
  func setAgents(_ agents: [AgentProfile]) { configuredAgents = agents }
  func blockNextList() { blockList = true }
  func releaseList() {
    listGate?.resume()
    listGate = nil
  }
  var heldCommands = 0
  private var holdSends = false
  private var holdCreates = false
  private var commandGates: [Int: CheckedContinuation<Bool, Never>] = [:]
  func holdCommands(send: Bool) {
    holdSends = send
    holdCreates = !send
  }
  func releaseCommand(_ index: Int, fail: Bool) {
    commandGates.removeValue(forKey: index)?.resume(returning: fail)
  }
  private func heldCommand() async throws {
    heldCommands += 1
    let index = heldCommands
    let fail = await withCheckedContinuation { commandGates[index] = $0 }
    if fail { throw NessaGatewayError.disconnected }
  }
  private var block = false
  private var connectionGate: CheckedContinuation<Void, Never>?
  private var blockDisconnection = false
  private var disconnectionGate: CheckedContinuation<Void, Never>?
  var retiring = false
  func blockNextDisconnection() { blockDisconnection = true }
  func releaseDisconnection() {
    disconnectionGate?.resume()
    disconnectionGate = nil
  }
  func blockNextConnection() { block = true }
  func releaseConnection() {
    connectionGate?.resume()
    connectionGate = nil
  }
  func connect(address: String, credential: String, instance: String) async throws {
    connections.append(address)
    if block {
      block = false
      await withCheckedContinuation { connectionGate = $0 }
    }
    if !online { throw URLError(.cannotConnectToHost) }
    await base.connect(address: address, credential: credential, instance: instance)
  }
  func disconnect() async {
    disconnects += 1
    if blockDisconnection {
      blockDisconnection = false
      retiring = true
      await withCheckedContinuation { disconnectionGate = $0 }
    }
    await base.disconnect()
  }
  func cut() async {
    online = false
    await base.disconnect()
  }
  func restore() { online = true }
  func list() async throws -> NessaConversationList {
    if blockList {
      blockList = false
      listing = true
      await withCheckedContinuation { listGate = $0 }
    }
    return try await base.list()
  }
  func agents() async throws -> [AgentProfile] {
    if let configuredAgents { return configuredAgents }
    return try await base.agents()
  }
  func read(_ id: String) async throws -> NessaConversationView { try await base.read(id) }
  func create(agent: String?, model: String?) async throws -> String {
    if holdCreates { try await heldCommand() }
    return try await base.create(agent: agent, model: model)
  }
  func send(_ text: String, attachments: [DraftAttachment], conversationID: String) async throws
    -> String
  {
    sends += 1
    if holdSends { try await heldCommand() }
    return try await base.send(text, attachments: attachments, conversationID: conversationID)
  }
  func answer(_ permission: NessaPermission, option: NessaPermission.Option, conversationID: String)
    async throws
  {
    try await base.answer(permission, option: option, conversationID: conversationID)
  }
  func delete(_ conversationID: String) async throws { try await base.delete(conversationID) }
  func listArchived() -> NessaConversationList { .init(conversations: [], complete: true) }
  func setArchived(_ archived: Bool, conversationID: String) {}
  func follow(_ id: String?, after: ConversationCursor?) async throws -> AsyncThrowingStream<
    ConversationUpdate, Error
  > {
    try await base.follow(id, after: after)
  }
}
@Test @MainActor func obsoleteDirectoryCannotEnterReplacementSnapshotScope() async throws {
  let repository = SwitchingGateway()
  let disk = InMemoryPhoneSnapshotStore()
  let snapshots = PhoneSnapshotSession(store: disk, coalescingDelay: .zero)
  let old = AgentProfile(id: "old", displayName: "Old directory")
  let next = AgentProfile(id: "new", displayName: "New directory")
  let model = MessagesViewModel(
    service: MessagingService(repository: repository, directory: repository),
    credentials: InMemoryCredentialStore(), preferences: InMemoryChatPreferences(),
    snapshots: snapshots)
  await repository.setAgents([old])
  await repository.blockNextList()
  let first = Task {
    await model.connect(address: "mock://old", credential: "old", instance: "phone")
  }
  await eventually { await repository.listing }
  await repository.setAgents([next])
  await model.connect(address: "mock://new", credential: "new", instance: "phone")
  await repository.releaseList()
  await first.value
  await snapshots.flush()
  let scope = PhoneCacheScope(address: "mock://new", credential: "new", instance: "phone")
  #expect(try await disk.load(scope)?.agents == [next])
  #expect(model.agentProfiles == [next])
  #expect(model.connected)
  await model.suspendConnection()
}
@Test(arguments: [false, true]) @MainActor
func interruptedCommandUnlocksUIAndCannotClearReplacementOperation(send: Bool) async throws {
  let repository = SwitchingGateway()
  let model = MessagesViewModel(
    service: MessagingService(repository: repository, directory: repository),
    credentials: InMemoryCredentialStore(), preferences: InMemoryChatPreferences(),
    recovery: ConnectionRecovery(waiting: SystemRecoveryWait()))
  await model.connect(address: "mock://gateway", credential: "first", instance: "phone")
  let id = try #require(model.conversations.first?.id)
  let inbox = Task { await model.watchInbox() }
  await repository.holdCommands(send: send)
  let first = Task {
    if send { return await model.send("Interrupted", to: id) }
    return await model.create() != nil
  }
  await eventually { await repository.heldCommands == 1 }
  await repository.cut()
  await eventually { model.reconnecting }
  await repository.restore()
  await eventually { model.connected && !model.reconnecting }
  #expect(!model.busy && !model.sending)
  let replacement = Task {
    if send { return await model.send("New intent", to: id) }
    return await model.create() != nil
  }
  await eventually { await repository.heldCommands == 2 }
  await repository.releaseCommand(1, fail: true)
  #expect(await first.value == false)
  #expect(send ? model.sending : model.busy)
  await repository.releaseCommand(2, fail: false)
  #expect(await replacement.value)
  #expect(!model.busy && !model.sending)
  #expect(await repository.heldCommands == 2)
  inbox.cancel()
  await model.suspendConnection()
}
/// Controls post-authentication failure/cancellation independently of socket replacement.
private actor LeasedGateway: MessagingRepository, AgentDirectory, ConnectionLeasing {
  let base = MockRepository()
  private var current: GatewayConnectionLease?
  private var firstAgents = true
  private var gate: CheckedContinuation<Void, Never>?
  private let cancelAfterAgents: Bool
  var entered = false
  var retiredCurrent = 0
  init(cancelAfterAgents: Bool) { self.cancelAfterAgents = cancelAfterAgents }
  func connect(address: String, credential: String, instance: String) async throws {
    _ = try await connectWithLease(address: address, credential: credential, instance: instance)
  }
  func connectWithLease(address: String, credential: String, instance: String) async throws
    -> GatewayConnectionLease
  {
    await base.connect(address: address, credential: credential, instance: instance)
    let lease = GatewayConnectionLease()
    current = lease
    return lease
  }
  func retire(_ lease: GatewayConnectionLease) async {
    if !cancelAfterAgents, !entered {
      entered = true
      await withCheckedContinuation { gate = $0 }
    }
    guard current == lease else { return }
    retiredCurrent += 1
    await disconnect()
  }
  func release() {
    gate?.resume()
    gate = nil
  }
  func agents() async throws -> [AgentProfile] {
    if firstAgents {
      firstAgents = false
      if cancelAfterAgents {
        entered = true
        await withCheckedContinuation { gate = $0 }
      } else {
        throw NessaGatewayError.rejected("Metadata unavailable")
      }
    }
    return try await base.agents()
  }
  func disconnect() async {
    current = nil
    await base.disconnect()
  }
  func list() async throws -> NessaConversationList { try await base.list() }
  func read(_ id: String) async throws -> NessaConversationView { try await base.read(id) }
  func create(agent: String?, model: String?) async throws -> String {
    try await base.create(agent: agent, model: model)
  }
  func send(_ text: String, attachments: [DraftAttachment], conversationID: String) async throws
    -> String
  {
    try await base.send(text, attachments: attachments, conversationID: conversationID)
  }
  func answer(_ permission: NessaPermission, option: NessaPermission.Option, conversationID: String)
    async throws
  {
    try await base.answer(permission, option: option, conversationID: conversationID)
  }
  func delete(_ id: String) async throws { try await base.delete(id) }
}
@Test(arguments: [false, true]) @MainActor
func obsoleteDialCleanupCannotDisconnectReadyReplacement(cancelAfterAgents: Bool) async throws {
  let repository = LeasedGateway(cancelAfterAgents: cancelAfterAgents)
  let model = MessagesViewModel(
    service: MessagingService(repository: repository, directory: repository),
    credentials: InMemoryCredentialStore(), preferences: InMemoryChatPreferences())
  let first = Task {
    await model.connect(address: "mock://old", credential: "old", instance: "phone")
  }
  await eventually { await repository.entered }
  if cancelAfterAgents { first.cancel() }
  await model.connect(address: "mock://new", credential: "new", instance: "phone")
  #expect(model.connected)
  await repository.release()
  await first.value
  #expect(model.connected)
  #expect(model.error == nil)
  #expect(await repository.retiredCurrent == 0)
  #expect(try await repository.list().conversations.count > 0)
  await model.suspendConnection()
}
@MainActor private func eventually(_ condition: () async -> Bool) async {
  let end = ContinuousClock.now + .seconds(3)
  while ContinuousClock.now < end {
    if await condition() { return }
    try? await Task.sleep(for: .milliseconds(2))
  }
  #expect(await condition())
}
@Test @MainActor func coldOfflineSnapshotIsVisibleButCannotSendOrCrossCredentials() async throws {
  let repository = SwitchingGateway()
  let store = InMemoryPhoneSnapshotStore()
  let snapshots = PhoneSnapshotSession(store: store, coalescingDelay: .zero)
  let first = MessagesViewModel(
    service: MessagingService(repository: repository, directory: repository),
    credentials: InMemoryCredentialStore(), preferences: InMemoryChatPreferences(),
    snapshots: snapshots)
  await first.connect(address: "mock://gateway", credential: "first", instance: "phone")
  let id = try #require(first.conversations.first?.id)
  await first.refresh(id)
  await snapshots.flush()
  await repository.cut()
  let next = MessagesViewModel(
    service: MessagingService(repository: repository),
    credentials: InMemoryCredentialStore(), preferences: InMemoryChatPreferences(),
    snapshots: PhoneSnapshotSession(store: store, coalescingDelay: .zero))
  await next.connect(address: "mock://gateway", credential: "first", instance: "phone")
  #expect(!next.connected)
  #expect(next.views[id] != nil)
  #expect(!next.conversations.isEmpty)
  #expect(await next.send("offline", to: id) == false)
  #expect(await repository.sends == 0)
  await next.connect(address: "mock://gateway", credential: "other", instance: "phone")
  #expect(next.views.isEmpty)
  #expect(next.conversations.isEmpty)
}
@Test @MainActor func lostFeedsRecoverWithNewRevisionAndFreshThreadUpdates() async throws {
  let repository = SwitchingGateway()
  let snapshots = PhoneSnapshotSession(store: InMemoryPhoneSnapshotStore(), coalescingDelay: .zero)
  let model = MessagesViewModel(
    service: MessagingService(repository: repository, directory: repository),
    credentials: InMemoryCredentialStore(), preferences: InMemoryChatPreferences(),
    snapshots: snapshots,
    recovery: ConnectionRecovery(waiting: SystemRecoveryWait()))
  await model.connect(address: "mock://gateway", credential: "first", instance: "phone")
  let id = try #require(model.conversations.first?.id)
  await model.refresh(id)
  let previous = model.views[id]
  let revision = model.connectionRevision
  let inbox = Task { await model.watchInbox() }
  let thread = Task { await model.watchConversation(id) }
  await eventually { model.views[id] != nil }
  await repository.cut()
  await eventually { model.reconnecting }
  #expect(model.views[id] == previous)
  await repository.restore()
  await eventually { model.connected && !model.reconnecting }
  #expect(model.connectionRevision > revision)
  let resumed = Task { await model.watchConversation(id) }
  #expect(await model.send("After reconnect", to: id))
  await eventually { model.views[id]?.messages.last?.userText == "After reconnect" }
  await model.suspendConnection()
  inbox.cancel()
  thread.cancel()
  resumed.cancel()
}
@Test @MainActor func backgroundThenForegroundReconnectsWithoutReplayingMessages() async throws {
  let repository = SwitchingGateway()
  let model = MessagesViewModel(
    service: MessagingService(repository: repository, directory: repository),
    credentials: InMemoryCredentialStore(), preferences: InMemoryChatPreferences(),
    recovery: ConnectionRecovery(waiting: SystemRecoveryWait()))
  await model.connect(address: "mock://gateway", credential: "first", instance: "phone")
  let oldRevision = model.connectionRevision
  await model.suspendConnection()
  #expect(!model.connected)
  #expect(await repository.disconnects == 1)
  model.resumeConnection()
  await eventually { model.connected }
  #expect(model.connectionRevision > oldRevision)
  #expect(await repository.connections.count == 2)
  #expect(await repository.sends == 0)
  await model.suspendConnection()
}
@Test @MainActor func manualConnectionChangeCancelsPreviousRecoveryDial() async throws {
  let repository = SwitchingGateway()
  let model = MessagesViewModel(
    service: MessagingService(repository: repository, directory: repository),
    credentials: InMemoryCredentialStore(), preferences: InMemoryChatPreferences(),
    recovery: ConnectionRecovery(waiting: SystemRecoveryWait()))
  await model.connect(address: "mock://first", credential: "first", instance: "phone")
  let inbox = Task { await model.watchInbox() }
  await repository.cut()
  await eventually {
    let count = await repository.connections.count
    return model.reconnecting && count == 2
  }
  await repository.restore()
  await model.connect(address: "mock://second", credential: "other", instance: "phone")
  try await Task.sleep(for: .milliseconds(550))
  #expect(await repository.connections == ["mock://first", "mock://first", "mock://second"])
  #expect(model.connected)
  #expect(!model.reconnecting)
  await model.suspendConnection()
  inbox.cancel()
}
private actor BlockedSnapshotSave: PhoneSnapshotStoring {
  var writes = 0
  private var continuation: CheckedContinuation<Void, Never>?
  func load(_ scope: PhoneCacheScope) -> PhoneSnapshot? { nil }
  func save(_ snapshot: PhoneSnapshot, scope: PhoneCacheScope) async {
    writes += 1
    if writes == 1 { await withCheckedContinuation { continuation = $0 } }
  }
  func release() {
    continuation?.resume()
    continuation = nil
  }
}
private actor BlockedHydration: PhoneSnapshotStoring {
  var entered = false
  private var continuation: CheckedContinuation<PhoneSnapshot?, Never>?
  func load(_ scope: PhoneCacheScope) async -> PhoneSnapshot? {
    entered = true
    return await withCheckedContinuation { continuation = $0 }
  }
  func save(_ snapshot: PhoneSnapshot, scope: PhoneCacheScope) {}
  func release() {
    continuation?.resume(returning: nil)
    continuation = nil
  }
}
private actor BlockedSecondHydration: PhoneSnapshotStoring {
  var loads = 0
  private var continuation: CheckedContinuation<PhoneSnapshot?, Never>?
  func load(_ scope: PhoneCacheScope) async -> PhoneSnapshot? {
    loads += 1
    if loads == 2 { return await withCheckedContinuation { continuation = $0 } }
    return nil
  }
  func save(_ snapshot: PhoneSnapshot, scope: PhoneCacheScope) {}
  func release() {
    continuation?.resume(returning: nil)
    continuation = nil
  }
}
@Test @MainActor func canceledRecoveryCannotPrepareCacheAfterDelayedRetirement() async throws {
  let repository = SwitchingGateway()
  let store = BlockedSecondHydration()
  let model = MessagesViewModel(
    service: MessagingService(repository: repository),
    credentials: InMemoryCredentialStore(), preferences: InMemoryChatPreferences(),
    snapshots: PhoneSnapshotSession(store: store, coalescingDelay: .zero),
    recovery: ConnectionRecovery(waiting: SystemRecoveryWait()))
  await model.connect(address: "mock://old", credential: "old", instance: "phone")
  await repository.blockNextDisconnection()
  let background = Task { await model.suspendConnection() }
  await eventually { await repository.retiring }
  model.resumeConnection()
  // Give the recovery task the actor so it queues behind the controlled retirement.
  try await Task.sleep(for: .milliseconds(10))
  let manual = Task {
    await model.connect(address: "mock://new", credential: "new", instance: "phone")
  }
  await eventually { await store.loads == 2 }
  await repository.releaseDisconnection()
  await background.value
  try await Task.sleep(for: .milliseconds(10))
  #expect(await store.loads == 2)
  await store.release()
  await manual.value
  #expect(model.connected)
  #expect(await repository.connections == ["mock://old", "mock://new"])
  await model.suspendConnection()
}
@Test @MainActor func foregroundCannotDialDuringManualHydration() async throws {
  let repository = SwitchingGateway()
  let store = BlockedHydration()
  let model = MessagesViewModel(
    service: MessagingService(repository: repository),
    credentials: InMemoryCredentialStore(), preferences: InMemoryChatPreferences(),
    snapshots: PhoneSnapshotSession(store: store, coalescingDelay: .zero),
    recovery: ConnectionRecovery(waiting: SystemRecoveryWait()))
  let manual = Task {
    await model.connect(address: "mock://first", credential: "first", instance: "phone")
  }
  await eventually { await store.entered }
  model.resumeConnection()
  try await Task.sleep(for: .milliseconds(10))
  #expect(await repository.connections.isEmpty)
  #expect(!model.reconnecting)
  await store.release()
  await manual.value
  #expect(await repository.connections.count == 1)
  #expect(model.connected)
  await model.suspendConnection()
}
@Test @MainActor func foregroundCannotReplaceAManualDialInProgress() async throws {
  let repository = SwitchingGateway()
  await repository.blockNextConnection()
  let model = MessagesViewModel(
    service: MessagingService(repository: repository),
    credentials: InMemoryCredentialStore(), preferences: InMemoryChatPreferences(),
    recovery: ConnectionRecovery(waiting: SystemRecoveryWait()))
  let manual = Task {
    await model.connect(address: "mock://first", credential: "first", instance: "phone")
  }
  await eventually { await repository.connections.count == 1 }
  model.resumeConnection()
  try await Task.sleep(for: .milliseconds(10))
  #expect(await repository.connections.count == 1)
  #expect(!model.reconnecting)
  await repository.releaseConnection()
  await manual.value
  #expect(model.connected)
  await model.suspendConnection()
}
@Test @MainActor func backgroundRetiresSocketBeforeBlockedCacheFlush() async throws {
  let repository = SwitchingGateway()
  let store = BlockedSnapshotSave()
  let snapshots = PhoneSnapshotSession(store: store, coalescingDelay: .zero)
  let model = MessagesViewModel(
    service: MessagingService(repository: repository),
    credentials: InMemoryCredentialStore(), preferences: InMemoryChatPreferences(),
    snapshots: snapshots)
  await model.connect(address: "mock://first", credential: "first", instance: "phone")
  await eventually { await store.writes == 1 }
  await model.suspendConnection()
  #expect(!model.connected)
  #expect(await repository.disconnects == 1)
  await store.release()
  await snapshots.flush()
}
