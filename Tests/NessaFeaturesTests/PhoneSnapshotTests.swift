import Foundation
import Testing

@testable import NessaFeatures

private func scope(_ credential: String = "private-test-credential") -> PhoneCacheScope {
  PhoneCacheScope(address: "wss://gateway/session", credential: credential, instance: "phone")
}
private func list(_ ids: [String], complete: Bool = true) -> NessaConversationList {
  NessaConversationList(
    conversations: ids.map {
      NessaConversation(conversationId: $0, title: $0, preview: nil, updatedAtMs: 0, running: false)
    }, complete: complete)
}
private func view(_ id: String) -> NessaConversationView {
  NessaConversationView(
    conversationId: id, messages: [], permissions: [], truncated: false,
    interactionViewError: nil, runtime: NessaRuntime(agent: "codex"))
}
private func update(_ id: String) throws -> ConversationUpdate {
  .view(try ConversationCursor(incarnation: "test", position: "1"), view(id))
}
private func example() -> PhoneSnapshot {
  var result = PhoneSnapshot()
  result.list = list(["a"])
  result.views = ["a": view("a")]
  result.recentViews = ["a"]
  return result
}
@Test func privateSnapshotSurvivesStoreRecreationAndIsCredentialScoped() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  try await PhoneSnapshotStore(root: root).save(example(), scope: scope())
  #expect(try await PhoneSnapshotStore(root: root).load(scope()) == example())
  #expect(try await PhoneSnapshotStore(root: root).load(scope("another-credential")) == nil)
  let file = root.appendingPathComponent(scope().key + ".json")
  #expect(
    !String(decoding: try Data(contentsOf: file), as: UTF8.self).contains("private-test-credential")
  )
  let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
  #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
}
@Test func snapshotRefusesCorruptionOversizeAndForeignViewIdentity() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  let file = root.appendingPathComponent(scope().key + ".json")
  let store = PhoneSnapshotStore(root: root, maximumBytes: 1024)
  try Data("broken".utf8).write(to: file)
  await #expect(throws: PhoneSnapshotError.corrupt) { try await store.load(scope()) }
  try Data(count: 1025).write(to: file)
  await #expect(throws: PhoneSnapshotError.quota) { try await store.load(scope()) }
  var mismatched = example()
  mismatched.views["a"] = view("foreign")
  try JSONEncoder().encode(mismatched).write(to: file)
  await #expect(throws: PhoneSnapshotError.corrupt) { try await store.load(scope()) }
  await #expect(throws: PhoneSnapshotError.corrupt) {
    try await store.save(mismatched, scope: scope())
  }
}
@Test func snapshotDoesNotFollowASymbolicLink() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  let outside = root.appendingPathComponent("outside.json")
  try JSONEncoder().encode(example()).write(to: outside)
  try FileManager.default.createSymbolicLink(
    at: root.appendingPathComponent(scope().key + ".json"), withDestinationURL: outside)
  await #expect(throws: PhoneSnapshotError.unavailable) {
    try await PhoneSnapshotStore(root: root).load(scope())
  }
}
@Test func inboxAbsenceDoesNotDeleteArchivedTranscriptAndConfirmedDeletionCannotResurrect()
  async throws
{
  let store = InMemoryPhoneSnapshotStore()
  let session = PhoneSnapshotSession(store: store, coalescingDelay: .zero)
  let (lease, _) = try await session.prepare(scope())
  await session.record(.list(list(["a"])), lease: lease)
  await session.record(try update("a"), lease: lease)
  await session.record(.list(list([], complete: false)), lease: lease)
  await session.flush()
  #expect(await store.load(scope())?.views["a"] != nil)
  await session.record(.list(list([])), lease: lease)
  await session.flush()
  #expect(await store.load(scope())?.views["a"] != nil)
  await session.remove("a", lease: lease)
  await session.record(.list(list(["a"])), lease: lease)
  await session.record(try update("a"), lease: lease)
  await session.flush()
  #expect(await store.load(scope())?.views.isEmpty == true)
  #expect(await store.load(scope())?.list?.conversations.isEmpty == true)
}
@Test func staleIdentityLeaseCannotMutateAReopenedIdentity() async throws {
  let store = InMemoryPhoneSnapshotStore()
  let session = PhoneSnapshotSession(store: store, coalescingDelay: .zero)
  let (old, _) = try await session.prepare(scope())
  _ = try await session.prepare(scope("different"))
  let (current, _) = try await session.prepare(scope())
  await session.record(.list(list(["new"])), lease: current)
  await session.record(.list(list(["stale"])), lease: old)
  await session.flush()
  #expect(await store.load(scope())?.list?.conversations.map(\.id) == ["new"])
}
private actor DelayedSaves: PhoneSnapshotStoring {
  var saved: PhoneSnapshot?
  var started = 0
  var simultaneous = 0
  var maximumSimultaneous = 0
  private var continuation: CheckedContinuation<Void, Never>?
  func load(_ scope: PhoneCacheScope) -> PhoneSnapshot? { saved }
  func save(_ snapshot: PhoneSnapshot, scope: PhoneCacheScope) async {
    started += 1
    simultaneous += 1
    maximumSimultaneous = max(maximumSimultaneous, simultaneous)
    if started == 1 { await withCheckedContinuation { continuation = $0 } }
    saved = snapshot
    simultaneous -= 1
  }
  func release() {
    continuation?.resume()
    continuation = nil
  }
}
@Test func reopeningSettlesPendingSnapshotBeforeHydrationAndPreservesOtherScopes() async throws {
  let store = InMemoryPhoneSnapshotStore()
  let session = PhoneSnapshotSession(store: store, coalescingDelay: .milliseconds(20))
  let (first, _) = try await session.prepare(scope())
  await session.record(.list(list(["a"])), lease: first)
  await session.record(try update("a"), lease: first)
  let (reopened, saved) = try await session.prepare(scope())
  #expect(saved?.views["a"] != nil)
  await session.recordAgents([], lease: reopened)
  let (other, _) = try await session.prepare(scope("other"))
  await session.record(.list(list(["b"])), lease: other)
  await session.record(try update("b"), lease: other)
  _ = try await session.prepare(scope())
  #expect(await store.load(scope())?.views["a"] != nil)
  #expect(await store.load(scope("other"))?.views["b"] != nil)
}
@Test func reopeningWaitsForDelayedOwnedWriteBeforeLoading() async throws {
  let store = DelayedSaves()
  let session = PhoneSnapshotSession(store: store, coalescingDelay: .zero)
  let (first, _) = try await session.prepare(scope())
  await session.record(.list(list(["a"])), lease: first)
  await session.record(try update("a"), lease: first)
  for _ in 0..<2000 {
    if await store.started == 1 { break }
    await Task.yield()
  }
  let reopening = Task { try await session.prepare(scope()) }
  try await Task.sleep(for: .milliseconds(10))
  await store.release()
  let (reopened, saved) = try await reopening.value
  #expect(saved?.views["a"] != nil)
  await session.recordAgents([], lease: reopened)
  await session.flush()
  #expect(await store.saved?.views["a"] != nil)
}
private actor DelayedLoads: PhoneSnapshotStoring {
  private var continuation: CheckedContinuation<PhoneSnapshot?, Never>?
  var loads = 0
  func load(_ scope: PhoneCacheScope) async -> PhoneSnapshot? {
    loads += 1
    if loads == 1 { return await withCheckedContinuation { continuation = $0 } }
    return nil
  }
  func save(_ snapshot: PhoneSnapshot, scope: PhoneCacheScope) {}
  func release(_ snapshot: PhoneSnapshot) {
    continuation?.resume(returning: snapshot)
    continuation = nil
  }
}
@Test @MainActor func chatRenderedBeforeHydrationShowsItsSavedMessagesAfterLoading() async throws {
  let repository = MockRepository()
  await repository.connect(address: "mock://history", credential: "", instance: "phone")
  let conversation = try #require(await repository.list().conversations.first)
  let history = try await repository.read(conversation.id)
  let turn = try #require(history.messages.first)
  var saved = PhoneSnapshot()
  saved.list = list([conversation.id])
  saved.views = [conversation.id: history]
  saved.recentViews = [conversation.id]
  let disk = DelayedLoads()
  let snapshots = PhoneSnapshotSession(store: disk, coalescingDelay: .zero)
  let model = MessagesViewModel(
    service: MessagingService(repository: repository), credentials: InMemoryCredentialStore(),
    preferences: InMemoryChatPreferences(), snapshots: snapshots)
  let connecting = Task {
    await model.connect(address: "mock://history", credential: "", instance: "phone")
  }
  for _ in 0..<2000 {
    if await disk.loads == 1 { break }
    await Task.yield()
  }
  #expect(await disk.loads == 1)
  // The chat can render while the disk actor is still loading its saved view.
  #expect(model.replyProjection(in: conversation.id).messages.isEmpty)
  await disk.release(saved)
  await connecting.value
  #expect(model.views[conversation.id] == history)
  #expect(!model.replyProjection(in: conversation.id).messages(in: turn.id).isEmpty)
  // Identical live data should preserve the already-visible saved history.
  await model.refresh(conversation.id)
  #expect(!model.replyProjection(in: conversation.id).messages(in: turn.id).isEmpty)
}
@Test func delayedHydrationCannotReplaceNewerIdentitySession() async throws {
  let store = DelayedLoads()
  let session = PhoneSnapshotSession(store: store, coalescingDelay: .zero)
  let old = Task { try await session.prepare(scope()) }
  for _ in 0..<2000 {
    if await store.loads == 1 { break }
    await Task.yield()
  }
  let (new, loaded) = try await session.prepare(scope("other"))
  #expect(loaded == nil)
  await store.release(example())
  await #expect(throws: CancellationError.self) { try await old.value }
  await session.record(.list(list(["new"])), lease: new)
  await session.flush()
}
@Test func snapshotWriterSerializesDelayedSaveAndNewDeletion() async throws {
  let store = DelayedSaves()
  let session = PhoneSnapshotSession(store: store, coalescingDelay: .zero)
  let (lease, _) = try await session.prepare(scope())
  await session.record(.list(list(["a"])), lease: lease)
  for _ in 0..<2000 {
    if await store.started == 1 { break }
    await Task.yield()
  }
  #expect(await store.started == 1)
  await session.remove("a", lease: lease)
  await store.release()
  await session.flush()
  #expect(await store.maximumSimultaneous == 1)
  #expect(await store.saved?.list?.conversations.isEmpty == true)
}
@Test func derivedSnapshotEvictsLeastRecentViewsWithinByteQuota() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  var saved = example()
  let onlyListBytes = try JSONEncoder().encode(PhoneSnapshot()).count + 300
  saved.views["a"] = NessaConversationView(
    conversationId: "a",
    messages: [
      NessaTurn(
        executionId: "turn", userText: String(repeating: "x", count: 2048),
        status: "completed", error: nil, parts: [])
    ], permissions: [], truncated: false,
    interactionViewError: nil, runtime: nil)
  let store = PhoneSnapshotStore(root: root, maximumBytes: onlyListBytes)
  try await store.save(saved, scope: scope())
  #expect(try await store.load(scope())?.views.isEmpty == true)
  #expect(try await store.load(scope())?.list?.conversations.map(\.id) == ["a"])
}
