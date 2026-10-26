import Foundation
import Testing

@testable import NessaFeatures

private func withdrawalScope(_ instance: String = "phone") -> PhoneCacheScope {
  .init(address: "wss://gateway/session", credential: "fixture-only", instance: instance)
}
private func withdrawalSnapshot(_ id: String) -> PhoneSnapshot {
  var result = PhoneSnapshot()
  result.list = .init(
    conversations: [
      .init(conversationId: id, title: id, preview: nil, updatedAtMs: 0, running: false)
    ],
    complete: true)
  return result
}

@Test func withdrawnSnapshotCannotReappearThroughAnOldWriterOrRecreatedStore() async throws {
  let root = profileTestRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let target = withdrawalScope()
  let priorWriter = PhoneSnapshotStore(root: root)
  try await priorWriter.save(withdrawalSnapshot("old"), scope: target)
  let file = root.appendingPathComponent(target.key + ".json")
  let before = try Data(contentsOf: file)
  try await PhoneSnapshotStore(root: root).withdraw(target)
  await #expect(throws: PhoneSnapshotError.withdrawn) { try await priorWriter.load(target) }
  await #expect(throws: PhoneSnapshotError.withdrawn) {
    try await priorWriter.save(withdrawalSnapshot("late"), scope: target)
  }
  let reopened = PhoneSnapshotStore(root: root)
  await #expect(throws: PhoneSnapshotError.withdrawn) { try await reopened.load(target) }
  #expect(try Data(contentsOf: file) == before)
  // Even physical snapshot absence cannot remove the independent withdrawal fence.
  try FileManager.default.removeItem(at: file)
  await #expect(throws: PhoneSnapshotError.withdrawn) { try await reopened.load(target) }
  let other = withdrawalScope("other")
  try await reopened.save(withdrawalSnapshot("other"), scope: other)
  #expect(try await reopened.load(other)?.list?.conversations.first?.id == "other")
  let marker = root.appendingPathComponent(SnapshotWithdrawalMarker.key(target) + ".json")
  #expect(!String(decoding: try Data(contentsOf: marker), as: UTF8.self).contains("fixture-only"))
}

@Test func withdrawalWriteFailureKeepsVisibilitySeparateFromDurability() async throws {
  for (mode, expected): (FaultingProfileFiles.Mode, PhoneSnapshotWithdrawalError) in [
    (.beforeWrite, .write(.notPublished, .unavailable, reconciliation: nil)),
    (.afterWrite, .write(.published, .unavailable, reconciliation: nil)),
    (.failedReadback, .write(.uncertain, .unavailable, reconciliation: .quota)),
    (.differentReadback, .write(.uncertain, .unavailable, reconciliation: nil)),
  ] {
    let root = profileTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = PhoneSnapshotStore(files: FaultingProfileFiles(root: root, mode: mode))
    await #expect(throws: expected) { try await store.withdraw(withdrawalScope()) }
    if mode == .afterWrite || mode == .failedReadback {
      let reopened = PhoneSnapshotStore(root: root)
      await #expect(throws: PhoneSnapshotError.withdrawn) {
        try await reopened.load(withdrawalScope())
      }
      // A fresh successful write, not failed-write readback, completes the retry.
      try await reopened.withdraw(withdrawalScope())
    }
  }
}

@Test func anExistingMarkerStillRequiresSuccessfulRepublicationAndSharesTheSnapshotLock()
  async throws
{
  let root = profileTestRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let target = withdrawalScope()
  let heldFiles = FaultingProfileFiles(root: root, mode: .heldWrite)
  let writing = Task {
    try await PhoneSnapshotStore(files: heldFiles).save(withdrawalSnapshot("first"), scope: target)
  }
  let entered = await heldFiles.waitForEntry()
  guard entered else {
    heldFiles.release.signal()
    _ = try? await writing.value
    Issue.record("snapshot write did not acquire its real scope lock")
    return
  }
  let store = PhoneSnapshotStore(root: root)
  await #expect(throws: PhoneSnapshotWithdrawalError.marker(.unavailable)) {
    try await store.withdraw(target)
  }
  await #expect(throws: PhoneSnapshotError.withdrawal(.unavailable)) {
    try await store.load(target)
  }
  heldFiles.release.signal()
  try await writing.value
  try await store.withdraw(target)
  let retry = PhoneSnapshotStore(files: FaultingProfileFiles(root: root, mode: .beforeWrite))
  // Prior visible bytes are not proof that this retry completed its flush.
  await #expect(
    throws: PhoneSnapshotWithdrawalError.write(.published, .unavailable, reconciliation: nil)
  ) {
    try await retry.withdraw(target)
  }
}

@Test func withdrawalMarkerCorruptionQuotaAndSymlinkNeverBecomeEmptyHistory() async throws {
  for kind in ["malformed", "foreign", "quota", "symlink"] {
    let root = profileTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = PhoneSnapshotStore(root: root, maximumBytes: 1024)
    let target = withdrawalScope()
    try await store.save(withdrawalSnapshot("old"), scope: target)
    let marker = root.appendingPathComponent(SnapshotWithdrawalMarker.key(target) + ".json")
    let failure: PhoneSnapshotMarkerFailure
    switch kind {
    case "quota":
      try Data(count: 1025).write(to: marker)
      failure = .quota
    case "foreign":
      try await store.withdraw(withdrawalScope("other"))
      let foreign = root.appendingPathComponent(
        SnapshotWithdrawalMarker.key(withdrawalScope("other")) + ".json")
      try Data(contentsOf: foreign).write(to: marker)
      failure = .corrupt
    case "symlink":
      try FileManager.default.createSymbolicLink(
        at: marker, withDestinationURL: root.appendingPathComponent(target.key + ".json"))
      failure = .unavailable
    default:
      try Data("{broken".utf8).write(to: marker)
      failure = .corrupt
    }
    await #expect(throws: PhoneSnapshotError.withdrawal(failure)) { try await store.load(target) }
    await #expect(throws: PhoneSnapshotError.withdrawal(failure)) {
      try await store.save(withdrawalSnapshot("late"), scope: target)
    }
    let session = PhoneSnapshotSession(store: store, coalescingDelay: .zero)
    await #expect(throws: PhoneSnapshotError.withdrawal(failure)) {
      try await session.prepare(target)
    }
    await #expect(throws: PhoneSnapshotError.withdrawal(failure)) {
      try await session.prepare(target)
    }
  }
}

private actor HeldWithdrawalStore: PhoneSnapshotStoring, PhoneSnapshotWithdrawing {
  var values: [String: PhoneSnapshot] = [:]
  var saves = 0
  var withdrawals = 0
  private var withdrawn: Set<String> = []
  private var held: CheckedContinuation<Void, Never>?
  private var entered: CheckedContinuation<Void, Never>?
  func load(_ scope: PhoneCacheScope) throws -> PhoneSnapshot? {
    guard !withdrawn.contains(scope.key) else { throw PhoneSnapshotError.withdrawn }
    return values[scope.key]
  }
  func save(_ value: PhoneSnapshot, scope: PhoneCacheScope) async throws {
    saves += 1
    if saves == 1 {
      await withCheckedContinuation {
        held = $0
        entered?.resume()
        entered = nil
      }
    }
    guard !withdrawn.contains(scope.key) else { throw PhoneSnapshotError.withdrawn }
    values[scope.key] = value
  }
  func waitForSave() async {
    if held != nil { return }
    await withCheckedContinuation { entered = $0 }
  }
  func release() {
    held?.resume()
    held = nil
  }
  func withdraw(_ scope: PhoneCacheScope) {
    withdrawals += 1
    withdrawn.insert(scope.key)
  }
}

@Test func withdrawalFencesBeforeHeldSaveSettlesAndPreservesOtherScopes() async throws {
  let store = HeldWithdrawalStore()
  let session = PhoneSnapshotSession(store: store, coalescingDelay: .zero)
  let target = withdrawalScope()
  let (old, _) = try await session.prepare(target)
  await session.record(.list(withdrawalSnapshot("first").list!), lease: old)
  await store.waitForSave()
  await session.record(.list(withdrawalSnapshot("queued").list!), lease: old)
  let withdrawing = Task { try await session.withdraw(target) }
  for _ in 0..<2000 {
    if await session.withdrawalFailure(target) != nil { break }
    await Task.yield()
  }
  guard await session.withdrawalFailure(target) == .withdrawn else {
    await store.release()
    _ = try? await withdrawing.value
    Issue.record("withdrawal failed to establish the admission fence")
    return
  }
  #expect(await store.withdrawals == 0)
  await #expect(throws: PhoneSnapshotError.withdrawn) { try await session.prepare(target) }
  await session.record(.list(withdrawalSnapshot("late").list!), lease: old)
  // Waiter cancellation does not abandon the already-requested cache suppression.
  withdrawing.cancel()
  await store.release()
  try await withdrawing.value
  #expect(await store.saves == 1)
  #expect(await store.withdrawals == 1)
  let other = withdrawalScope("other")
  let (current, _) = try await session.prepare(other)
  await session.record(.list(withdrawalSnapshot("other").list!), lease: current)
  await session.flush()
  #expect(try await store.load(other)?.list?.conversations.first?.id == "other")
  await #expect(throws: PhoneSnapshotError.withdrawn) { try await store.load(target) }
}

@Test func failedWithdrawalStillFencesTheLiveSessionAndRetryIsExplicit() async throws {
  let root = profileTestRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = PhoneSnapshotStore(files: FaultingProfileFiles(root: root, mode: .beforeWrite))
  let session = PhoneSnapshotSession(store: store)
  let (lease, _) = try await session.prepare(withdrawalScope())
  await #expect(
    throws: PhoneSnapshotWithdrawalError.write(.notPublished, .unavailable, reconciliation: nil)
  ) {
    try await session.withdraw(withdrawalScope())
  }
  await #expect(throws: PhoneSnapshotError.withdrawn) {
    try await session.prepare(withdrawalScope())
  }
  await session.record(.list(withdrawalSnapshot("late").list!), lease: lease)
  await session.flush()
  #expect(try await PhoneSnapshotStore(root: root).load(withdrawalScope()) == nil)
}

private struct NoWithdrawalStore: PhoneSnapshotStoring {
  func load(_ scope: PhoneCacheScope) -> PhoneSnapshot? { nil }
  func save(_ snapshot: PhoneSnapshot, scope: PhoneCacheScope) {}
}

@Test func absentWithdrawalCapabilityCannotPretendItPersistedAFence() async throws {
  let session = PhoneSnapshotSession(store: NoWithdrawalStore())
  _ = try await session.prepare(withdrawalScope())
  await #expect(throws: PhoneSnapshotWithdrawalError.unsupported) {
    try await session.withdraw(withdrawalScope())
  }
  await #expect(throws: PhoneSnapshotError.withdrawn) {
    try await session.prepare(withdrawalScope())
  }
}

private actor WithdrawalDialProbe: MessagingRepository {
  var connects = 0
  func connect(address: String, credential: String, instance: String) { connects += 1 }
  func disconnect() {}
  func list() -> NessaConversationList { .init(conversations: [], complete: true) }
  func read(_ id: String) throws -> NessaConversationView { throw NessaGatewayError.disconnected }
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

@Test @MainActor func withdrawnLegacyHydrationCannotDialOrPublishStaleHistory() async throws {
  let store = InMemoryPhoneSnapshotStore()
  try await store.save(withdrawalSnapshot("old"), scope: withdrawalScope())
  await store.withdraw(withdrawalScope())
  let repository = WithdrawalDialProbe()
  let model = MessagesViewModel(
    service: MessagingService(repository: repository), credentials: InMemoryCredentialStore(),
    preferences: InMemoryChatPreferences(), snapshots: PhoneSnapshotSession(store: store))
  await model.connect(
    address: "wss://gateway/session", credential: "fixture-only", instance: "phone")
  #expect(await repository.connects == 0)
  #expect(!model.connected && model.conversations.isEmpty && model.views.isEmpty)
  #expect(model.error != nil)
}
