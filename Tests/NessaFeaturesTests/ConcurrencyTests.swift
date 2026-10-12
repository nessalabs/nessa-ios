import Combine
import Foundation
import Testing

@testable import NessaFeatures

private actor DelayedRepository: MessagingRepository {
  private var reads: [CheckedContinuation<NessaConversationView, Error>?] = []
  var readCount: Int { reads.count }
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
  #expect(model.agentPreviews["thread"] == nil)
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
