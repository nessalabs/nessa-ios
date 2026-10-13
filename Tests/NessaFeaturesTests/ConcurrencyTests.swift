import Combine
import Foundation
import Testing

@testable import NessaFeatures

private actor DelayedRepository: MessagingRepository {
  private var reads: [CheckedContinuation<NessaConversationView, Error>?] = []
  var readCount: Int { reads.count }
  private(set) var totalReadCount = 0
  private var readWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
  private var lists: [CheckedContinuation<NessaConversationList, Error>?] = []
  private var listWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
  private var delayLists = false
  private var failList = false
  func rejectLists() { failList = true }
  private var sends: [CheckedContinuation<Void, Error>] = []
  private var sendWaiter: CheckedContinuation<Void, Never>?
  private var immediateRead: NessaConversationView?
  func useImmediateRead(_ view: NessaConversationView) { immediateRead = view }
  func waitForSend() async {
    if !sends.isEmpty { return }
    await withCheckedContinuation { sendWaiter = $0 }
  }
  func finishSend(_ result: Result<Void, Error>) { sends.removeFirst().resume(with: result) }

  func connect(address: String, credential: String, instance: String) {}
  func disconnect() {}
  func create(agent: String?, model: String?) -> String { "created" }
  func send(_ text: String, attachments: [DraftAttachment], conversationID: String) async throws
    -> String
  {
    try await withCheckedThrowingContinuation { continuation in
      sends.append(continuation)
      sendWaiter?.resume()
      sendWaiter = nil
    }
    return "sent"
  }
  func delete(_ conversationID: String) {}
  func answer(_ permission: NessaPermission, option: NessaPermission.Option, conversationID: String)
  {}
  func list() async throws -> NessaConversationList {
    if failList { throw NessaGatewayError.rejected("Unavailable") }
    if !delayLists { return NessaConversationList(conversations: [], complete: true) }
    return try await withCheckedThrowingContinuation { continuation in
      lists.append(continuation)
      for waiter in listWaiters where lists.count >= waiter.0 { waiter.1.resume() }
      listWaiters.removeAll { lists.count >= $0.0 }
    }
  }
  func read(_ id: String) async throws -> NessaConversationView {
    totalReadCount += 1
    if let immediateRead { return immediateRead }
    return try await withCheckedThrowingContinuation { continuation in
      reads.append(continuation)
      for waiter in readWaiters where reads.count >= waiter.0 { waiter.1.resume() }
      readWaiters.removeAll { reads.count >= $0.0 }
    }
  }
  func waitForReads(_ count: Int) async {
    if reads.count >= count { return }
    await withCheckedContinuation { readWaiters.append((count, $0)) }
  }
  func beginDelayedLists() { delayLists = true }
  func waitForLists(_ count: Int) async {
    if lists.count >= count { return }
    await withCheckedContinuation { listWaiters.append((count, $0)) }
  }
  func finishRead(_ index: Int, result: Result<NessaConversationView, Error>) {
    reads[index]?.resume(with: result)
    reads[index] = nil
  }
  func finishList(_ index: Int, id: String) {
    lists[index]?.resume(
      returning: NessaConversationList(
        conversations: [
          NessaConversation(
            conversationId: id, title: id, preview: nil, updatedAtMs: 0, running: false)
        ], complete: true))
    lists[index] = nil
  }
}

@Test @MainActor
func staleReadFailureCannotDisconnectAfterNewerSuccessfulRead() async {
  let repository = DelayedRepository()
  let model = MessagesViewModel(
    service: MessagingService(repository: repository),
    credentials: InMemoryCredentialStore(), preferences: InMemoryChatPreferences())
  await model.connect(address: "mock://concurrency", credential: "", instance: "test")
  let old = Task { await model.refresh("thread") }
  await repository.waitForReads(1)
  let latest = Task { await model.refresh("thread") }
  await repository.waitForReads(2)
  let thread = NessaConversationView(
    conversationId: "thread", messages: [], permissions: [],
    truncated: false, interactionViewError: nil, runtime: nil)
  await repository.finishRead(1, result: .success(thread))
  await latest.value
  await repository.finishRead(0, result: .failure(NessaGatewayError.disconnected))
  await old.value
  #expect(model.connected)
  #expect(model.error == nil)
  #expect(model.views["thread"] == thread)
}

@Test @MainActor
func olderInboxResponseCannotHideNewConversation() async throws {
  let repository = DelayedRepository()
  let model = MessagesViewModel(
    service: MessagingService(repository: repository),
    credentials: InMemoryCredentialStore(), preferences: InMemoryChatPreferences())
  await model.connect(address: "mock://concurrency", credential: "", instance: "test")
  await repository.beginDelayedLists()
  let old = Task { try await model.refreshList() }
  await repository.waitForLists(1)
  let latest = Task { try await model.refreshList() }
  await repository.waitForLists(2)
  await repository.finishList(1, id: "created")
  try await latest.value
  await repository.finishList(0, id: "old")
  try await old.value
  #expect(model.conversations.map(\.id) == ["created"])
}

@Test @MainActor
func deletionInvalidatesPendingInboxThreadAndPreview() async throws {
  let repository = DelayedRepository()
  let model = MessagesViewModel(
    service: MessagingService(repository: repository),
    credentials: InMemoryCredentialStore(), preferences: InMemoryChatPreferences())
  await model.connect(address: "mock://deletion", credential: "", instance: "test")
  model.conversations = [
    NessaConversation(
      conversationId: "thread", title: "thread", preview: nil,
      updatedAtMs: 0, running: false)
  ]
  await repository.beginDelayedLists()
  let list = Task { try await model.refreshList() }
  let read = Task { await model.refresh("thread") }
  let preview = Task { await model.loadPreview("thread") }
  await repository.waitForLists(1)
  await repository.waitForReads(2)
  await model.deleteConversation(for: "thread")
  await repository.finishList(0, id: "thread")
  let thread = NessaConversationView(
    conversationId: "thread", messages: [], permissions: [],
    truncated: false, interactionViewError: nil, runtime: nil)
  await repository.finishRead(0, result: .success(thread))
  await repository.finishRead(1, result: .success(thread))
  try await list.value
  await read.value
  await preview.value
  #expect(model.conversations.isEmpty)
  #expect(model.views["thread"] == nil)
  #expect(model.previewState(for: "thread") == .unavailable)
}

@Test @MainActor
func staleSendCompletionCannotMutateReplacementSession() async {
  let repository = DelayedRepository()
  let model = MessagesViewModel(
    service: MessagingService(repository: repository),
    credentials: InMemoryCredentialStore(), preferences: InMemoryChatPreferences())
  await model.connect(address: "mock://first", credential: "", instance: "test")
  let send = Task {
    await model.send(
      "hello",
      reply: MessageReply(id: "original", author: "Agent", text: "Original"), to: "first-thread")
  }
  await repository.waitForSend()
  await model.connect(address: "mock://second", credential: "", instance: "test")
  await repository.finishSend(.success(()))
  #expect(await send.value)
  #expect(model.views.isEmpty)
  #expect(model.error == nil)
  #expect(model.connected)
  #expect(!model.sending)
  #expect(model.replyTargets.isEmpty)
}

@Test @MainActor
func creationNavigatesAfterAcknowledgementWithoutWaitingForAnEmptyRead() async {
  let repository = DelayedRepository()
  let model = MessagesViewModel(
    service: MessagingService(repository: repository),
    credentials: InMemoryCredentialStore(), preferences: InMemoryChatPreferences())
  await model.connect(address: "mock://creation", credential: "", instance: "test")
  let id = await model.create(agent: "agent")
  #expect(id == "created")
  #expect(await repository.readCount == 0)
  #expect(model.views["created"]?.messages.isEmpty == true)
  #expect(model.agentID(for: "created") == "agent")
  #expect(!model.busy)
}

@Test @MainActor
func unchangedPollDoesNotPublishScreenUpdates() async throws {
  let repository = DelayedRepository()
  let model = MessagesViewModel(
    service: MessagingService(repository: repository),
    credentials: InMemoryCredentialStore(), preferences: InMemoryChatPreferences())
  await model.connect(address: "mock://poll", credential: "", instance: "test")
  await repository.useImmediateRead(
    NessaConversationView(
      conversationId: "thread", messages: [],
      permissions: [], truncated: false, interactionViewError: nil, runtime: nil))
  await model.refresh("thread")
  var updates = 0
  let subscription = model.objectWillChange.sink { updates += 1 }
  await model.refresh("thread")
  try await model.refreshList()
  #expect(updates == 0)
  withExtendedLifetime(subscription) {}
}

private final class RecordingCredentials: NessaCredentialStoring, @unchecked Sendable {
  private let lock = NSLock()
  private var value: String?
  func load() -> String? { lock.withLock { value } }
  func save(_ credential: String) { lock.withLock { value = credential } }
}

@Test @MainActor
func failedReconnectKeepsCredentialAndClearsPreviousInbox() async throws {
  let repository = DelayedRepository()
  let credentials = RecordingCredentials()
  let model = MessagesViewModel(
    service: MessagingService(repository: repository),
    credentials: credentials, preferences: InMemoryChatPreferences())
  await model.connect(address: "mock://first", credential: "first", instance: "test")
  model.conversations = [
    NessaConversation(
      conversationId: "thread", title: "thread", preview: nil,
      updatedAtMs: 0, running: false)
  ]
  model.togglePin("thread")
  await repository.rejectLists()
  await model.connect(address: "mock://second", credential: "second", instance: "test")
  #expect(!model.connected)
  #expect(model.conversations.isEmpty)
  #expect(model.pinnedChats.isEmpty)
  #expect(credentials.load() == "first")
  #expect(model.error != nil)
}

@Test @MainActor
func staleSendFailureCannotPublishErrorInReplacementSession() async {
  let repository = DelayedRepository()
  let model = MessagesViewModel(
    service: MessagingService(repository: repository),
    credentials: InMemoryCredentialStore(), preferences: InMemoryChatPreferences())
  await model.connect(address: "mock://first", credential: "", instance: "test")
  let send = Task { await model.send("hello", to: "first-thread") }
  await repository.waitForSend()
  await model.connect(address: "mock://second", credential: "", instance: "test")
  await repository.finishSend(.failure(NessaGatewayError.disconnected))
  #expect(await send.value == false)
  #expect(model.error == nil)
  #expect(model.connected)
}

private func previewThread(_ text: String? = nil) -> NessaConversationView {
  NessaConversationView(
    conversationId: "thread",
    messages: text.map {
      [NessaTurn(executionId: "turn", userText: $0, status: "done", error: nil, parts: [])]
    } ?? [],
    permissions: [], truncated: false, interactionViewError: nil, runtime: nil)
}
@MainActor private func previewModel(_ repository: DelayedRepository, alias: Bool = false) async
  -> MessagesViewModel
{
  let preferences = InMemoryChatPreferences()
  if alias {
    preferences.save(["codex": "thread"], forKey: "nessa.agentThreads.mock://preview:test")
  }
  let model = MessagesViewModel(
    service: MessagingService(repository: repository),
    credentials: InMemoryCredentialStore(), preferences: preferences)
  await model.connect(address: "mock://preview", credential: "", instance: "test")
  model.conversations = [
    NessaConversation(
      conversationId: "thread", title: "thread", preview: nil, updatedAtMs: 0, running: false)
  ]
  return model
}
@Test @MainActor func loadedAndOfflinePreviewsReuseHistoryWithoutReadingAgain() async {
  let repository = DelayedRepository()
  let model = await previewModel(repository)
  let view = previewThread("Already loaded")
  await repository.useImmediateRead(view)
  await model.refresh("thread")
  #expect(await repository.totalReadCount == 1)
  #expect(model.previewState(for: "thread") == .available(view))
  await model.loadPreview("thread")
  #expect(await repository.totalReadCount == 1)
  await model.suspendConnection()
  await model.loadPreview("thread")
  #expect(model.previewState(for: "thread") == .available(view))
  #expect(await repository.totalReadCount == 1)
}
@Test @MainActor func emptyAndRefusedPreviewReadsSettleInsteadOfLoadingForever() async {
  for fails in [false, true] {
    let repository = DelayedRepository()
    let model = await previewModel(repository)
    let pending = Task { await model.loadPreview("thread") }
    await repository.waitForReads(1)
    #expect(model.previewState(for: "thread") == .loading)
    await repository.finishRead(
      0, result: fails ? .failure(NessaGatewayError.disconnected) : .success(previewThread()))
    await pending.value
    #expect(model.previewState(for: "thread") == (fails ? .unavailable : .empty))
    #expect(model.connected)
    #expect(model.error == nil)
    if !fails {
      await model.loadPreview("thread")
      #expect(await repository.totalReadCount == 1)
    }
  }
}
@Test @MainActor func previewAliasesShareReadAndObserverCancellationDoesNotCancelOwner() async {
  let repository = DelayedRepository()
  let model = await previewModel(repository, alias: true)
  let first = Task { await model.loadPreview("codex") }
  await repository.waitForReads(1)
  let second = Task { await model.loadPreview("thread") }
  await Task.yield()
  #expect(model.previewState(for: "codex") == .loading)
  #expect(model.previewState(for: "thread") == .loading)
  #expect(await repository.totalReadCount == 1)
  first.cancel()
  let view = previewThread("Shared")
  await repository.finishRead(0, result: .success(view))
  await first.value
  await second.value
  #expect(model.previewState(for: "codex") == .available(view))
  #expect(model.previewState(for: "thread") == .available(view))
}
@Test @MainActor func newerConversationWinsOverLatePreviewResponse() async {
  let repository = DelayedRepository()
  let model = await previewModel(repository)
  let old = Task { await model.loadPreview("thread") }
  await repository.waitForReads(1)
  let current = Task { await model.refresh("thread") }
  await repository.waitForReads(2)
  let latest = previewThread("Latest")
  await repository.finishRead(1, result: .success(latest))
  await current.value
  #expect(model.previewState(for: "thread") == .available(latest))
  await repository.finishRead(0, result: .success(previewThread("Stale")))
  await old.value
  #expect(model.previewState(for: "thread") == .available(latest))
}
@Test @MainActor func oldPreviewCleanupCannotClearReplacementReadAcrossReconnect() async {
  let repository = DelayedRepository()
  let model = await previewModel(repository)
  let old = Task { await model.loadPreview("thread") }
  await repository.waitForReads(1)
  await model.connect(address: "mock://preview", credential: "", instance: "test")
  model.conversations = [
    NessaConversation(
      conversationId: "thread", title: "thread", preview: nil, updatedAtMs: 0, running: false)
  ]
  let current = Task { await model.loadPreview("thread") }
  await repository.waitForReads(2)
  await repository.finishRead(0, result: .success(previewThread("Obsolete")))
  await old.value
  #expect(model.previewState(for: "thread") == .loading)
  await repository.finishRead(1, result: .success(previewThread("Replacement")))
  await current.value
  #expect(model.previewState(for: "thread") == .available(previewThread("Replacement")))
}
@Test @MainActor func suspensionEndsPreviewLoadingAndRejectsItsLateRead() async {
  let repository = DelayedRepository()
  let model = await previewModel(repository)
  let pending = Task { await model.loadPreview("thread") }
  await repository.waitForReads(1)
  await model.suspendConnection()
  #expect(model.previewState(for: "thread") == .unavailable)
  await repository.finishRead(0, result: .success(previewThread("Late")))
  await pending.value
  #expect(model.previewState(for: "thread") == .unavailable)
}
@Test @MainActor func frozenChatMenuCannotFollowAnAliasIntoAnotherConversation() async {
  let repository = DelayedRepository()
  let model = await previewModel(repository, alias: true)
  let selection = ChatMenuSelection(identifier: "codex", store: model)
  #expect(selection.conversationID == "thread")
  #expect(selection.isCurrent(in: model))
  // A current read can update the agent's preferred thread within the same profile.
  let newView = NessaConversationView(
    conversationId: "other", messages: [], permissions: [], truncated: false,
    interactionViewError: nil, runtime: .init(agent: "codex"))
  await repository.useImmediateRead(newView)
  await model.refresh("other")
  #expect(model.deliveryScopeRevision == selection.scope)
  #expect(!selection.isCurrent(in: model))
}

@Test @MainActor func automaticConnectionLossReleasesObsoletePreviewOwnership() async {
  let repository = DelayedRepository()
  let model = await previewModel(repository)
  let preview = Task { await model.loadPreview("thread") }
  await repository.waitForReads(1)
  let failing = Task { await model.refresh("thread") }
  await repository.waitForReads(2)
  await repository.finishRead(1, result: .failure(NessaGatewayError.disconnected))
  await failing.value
  #expect(!model.connected)
  #expect(model.previewState(for: "thread") == .unavailable)
  // A later ready publication may permit a fresh read without joining the old token.
  model.connected = true
  let replacement = Task { await model.loadPreview("thread") }
  await repository.waitForReads(3)
  await repository.finishRead(0, result: .success(previewThread("Old connection")))
  await preview.value
  #expect(model.previewState(for: "thread") == .loading)
  await repository.finishRead(2, result: .success(previewThread("New connection")))
  await replacement.value
  #expect(model.previewState(for: "thread") == .available(previewThread("New connection")))
}
@Test @MainActor func legacyPinnedDeleteUsesFrozenConversationAndClearsAliasPreferences()
  async throws
{
  let repository = DelayedRepository()
  let model = await previewModel(repository, alias: true)
  model.togglePin("codex")
  model.markUnread("codex")
  model.toggleAlerts("codex")
  let selection = ChatMenuSelection(identifier: "codex", store: model)
  var confirmed: String?
  let actions = chatMenuActions(selection: selection, store: model, onDelete: { confirmed = $0 })
  try #require(actions.first { $0.id == "delete" }).perform()
  #expect(confirmed == "thread")
  await model.deleteConversations([try #require(confirmed)])
  #expect(!model.hasConversation("codex"))
  #expect(!model.isPinned("codex"))
  #expect(!model.unreadChats.contains("codex"))
  #expect(!model.mutedChats.contains("codex"))
}
