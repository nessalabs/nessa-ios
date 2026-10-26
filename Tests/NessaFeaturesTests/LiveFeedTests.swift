import Foundation
import Testing

@testable import NessaFeatures

private func data(_ string: String) -> Data { Data(string.utf8) }
private func frame(_ subscription: String, conversation: String = "chat", position: Int) -> Data {
  data(
    """
    {"subscriptionId":"\(subscription)","cursor":{"incarnation":"history","position":"\(position)"},
    "view":{"conversationId":"\(conversation)","messages":[],"permissions":[],"truncated":false}}
    """)
}
@Test func cursorRejectsNoncanonicalOrOverflowingPositions() throws {
  for value in ["", "01", "-1", "+1", "1.0", "18446744073709551616", "١"] {
    #expect(throws: NessaGatewayError.self) {
      try ConversationCursor(incarnation: "a", position: value)
    }
  }
  #expect(
    try ConversationCursor(incarnation: "a", position: "18446744073709551615").offset == UInt64.max)
}
@Test func firstFrameIsHeldBeforeTheCallerStartsConsumingAndBurstIsBounded() async throws {
  var router = GatewaySubscriptions()
  let stream = try router.prepare("request", conversationID: "chat", cancelled: {})
  #expect(try router.activate("request", data: data("{\"subscriptionId\":\"sub\"}")) == nil)
  for index in 1...1000 {
    #expect(router.receive("conversation.view", payload: frame("sub", position: index)) == nil)
  }
  var iterator = stream.makeAsyncIterator()
  guard case .view(let cursor, _) = try await iterator.next() else {
    Issue.record("Expected held replacement")
    return
  }
  #expect(cursor.offset == 1000)
  router.finishAll(NessaGatewayError.disconnected)
}
@Test func cancellationBeforeAcknowledgementCleansUpTheExactRegisteredID() async throws {
  var router = GatewaySubscriptions()
  let stream = try router.prepare("pending", conversationID: "chat", cancelled: {})
  #expect(router.cancel("pending") == nil)
  #expect(try router.activate("pending", data: data("{\"subscriptionId\":\"late\"}")) == "late")
  #expect(router.count == 0)
  var iterator = stream.makeAsyncIterator()
  #expect(try await iterator.next() == nil)
}
@Test func canceledSubscriptionIgnoresLateFramesAndCannotCancelAReplacement() async throws {
  var router = GatewaySubscriptions()
  let first = try router.prepare("old", conversationID: "chat", cancelled: {})
  _ = try router.activate("old", data: data("{\"subscriptionId\":\"old-sub\"}"))
  #expect(router.cancel("old") == "old-sub")
  let second = try router.prepare("new", conversationID: "chat", cancelled: {})
  _ = try router.activate("new", data: data("{\"subscriptionId\":\"new-sub\"}"))
  #expect(router.cancel("old") == nil)
  _ = router.receive("conversation.view", payload: frame("old-sub", position: 999))
  _ = router.receive("conversation.view", payload: frame("new-sub", position: 2))
  var iterator = second.makeAsyncIterator()
  guard case .view(let cursor, _) = try await iterator.next() else {
    Issue.record("Expected current view")
    return
  }
  #expect(cursor.offset == 2)
  var old = first.makeAsyncIterator()
  #expect(try await old.next() == nil)
  router.finishAll(NessaGatewayError.disconnected)
}
@Test func foreignViewFailsOnlyItsOwnSubscription() async throws {
  var router = GatewaySubscriptions()
  let chat = try router.prepare("chat", conversationID: "chat", cancelled: {})
  let inbox = try router.prepare("inbox", conversationID: nil, cancelled: {})
  _ = try router.activate("chat", data: data("{\"subscriptionId\":\"chat-sub\"}"))
  _ = try router.activate("inbox", data: data("{\"subscriptionId\":\"inbox-sub\"}"))
  #expect(
    router.receive(
      "conversation.view", payload: frame("chat-sub", conversation: "foreign", position: 1))
      == "chat-sub")
  _ = router.receive(
    "conversation.listed",
    payload: data(
      "{\"subscriptionId\":\"inbox-sub\",\"list\":{\"conversations\":[],\"complete\":true}}"))
  var failed = chat.makeAsyncIterator()
  await #expect(throws: NessaGatewayError.self) { _ = try await failed.next() }
  var good = inbox.makeAsyncIterator()
  guard case .list(let list) = try await good.next() else {
    Issue.record("Inbox should survive")
    return
  }
  #expect(list.complete)
  router.finishAll(NessaGatewayError.disconnected)
}
@Test func terminalRefusalAndSocketFailureRetireTheirFeeds() async throws {
  var router = GatewaySubscriptions()
  let stream = try router.prepare("chat", conversationID: "chat", cancelled: {})
  _ = try router.activate("chat", data: data("{\"subscriptionId\":\"sub\"}"))
  _ = router.receive(
    "conversation.subscriptionEnded",
    payload: data("{\"subscriptionId\":\"sub\",\"reason\":\"refused\",\"code\":\"forbidden\"}"))
  var iterator = stream.makeAsyncIterator()
  do {
    _ = try await iterator.next()
    Issue.record("Expected terminal refusal")
  } catch let ended as ConversationFeedEnded {
    #expect(ended.reason == .refused)
    #expect(ended.code == "forbidden")
  }
  let pending = try router.prepare("pending", conversationID: nil, cancelled: {})
  router.finishAll(NessaGatewayError.disconnected)
  var waiting = pending.makeAsyncIterator()
  await #expect(throws: NessaGatewayError.self) { _ = try await waiting.next() }
  #expect(router.count == 0)
}
@Test @MainActor func mockLiveFeedUpdatesTheVisibleThreadWithoutPolling() async throws {
  let repository = MockRepository()
  let model = NessaDependencies.development(repository: repository).makeMessagesViewModel()
  await model.connect(address: "mock://feeds", credential: "", instance: "test")
  let id = try #require(await model.create())
  let watch = Task { await model.watchConversation(id) }
  defer { watch.cancel() }
  let execution = try await repository.send("Live event", conversationID: id)
  for _ in 0..<2000 {
    if model.views[id]?.messages.last?.id == execution { break }
    await Task.yield()
  }
  #expect(model.views[id]?.messages.last?.userText == "Live event")
  #expect(model.views[id]?.messages.last?.status == "running")
}

private actor ScriptedFeedRepository: MessagingRepository, ConversationFollowing {
  private let base = MockRepository()
  private let batches: [[ConversationUpdate]]
  private let firstEnd: ConversationFeedEnded.Reason?
  private var calls: [ConversationCursor?] = []
  var requested: [ConversationCursor?] { calls }
  init(batches: [[ConversationUpdate]], firstEnd: ConversationFeedEnded.Reason? = nil) {
    self.batches = batches
    self.firstEnd = firstEnd
  }
  func follow(_ id: String?, after: ConversationCursor?) -> AsyncThrowingStream<
    ConversationUpdate, Error
  > {
    let index = calls.count
    calls.append(after)
    return AsyncThrowingStream { continuation in
      for update in batches[min(index, batches.count - 1)] { continuation.yield(update) }
      if index == 0, let firstEnd {
        continuation.finish(throwing: ConversationFeedEnded(reason: firstEnd, code: nil))
      } else {
        continuation.finish()
      }
    }
  }
  func connect(address: String, credential: String, instance: String) async throws {
    await base.connect(address: address, credential: credential, instance: instance)
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
  func delete(_ id: String) async throws { try await base.delete(id) }
  func listArchived() async throws -> NessaConversationList { try await base.listArchived() }
  func setArchived(_ archived: Bool, conversationID: String) async throws {
    try await base.setArchived(archived, conversationID: conversationID)
  }
  func answer(_ permission: NessaPermission, option: NessaPermission.Option, conversationID: String)
    async throws
  {
    try await base.answer(permission, option: option, conversationID: conversationID)
  }
  func disconnect() async { await base.disconnect() }
}
private actor AppliedCursors {
  var values: [ConversationCursor] = []
  func append(_ update: ConversationUpdate) {
    if case .view(let cursor, _) = update { values.append(cursor) }
  }
}
private func publication(_ position: String, incarnation: String = "history", id: String = "chat")
  throws -> ConversationUpdate
{
  .view(
    try ConversationCursor(incarnation: incarnation, position: position),
    NessaConversationView(
      conversationId: id, messages: [], permissions: [], truncated: false,
      interactionViewError: nil, runtime: nil))
}
@Test func watchDiscardsOlderSameIncarnationButAcceptsAReplacementHistory() async throws {
  let source = try ScriptedFeedRepository(batches: [
    [
      publication("10"), publication("9"),
      publication("11"), publication("1", incarnation: "replacement"),
    ]
  ])
  let applied = AppliedCursors()
  try await MessagingService(repository: source).watch("chat") { await applied.append($0) }
  #expect(await applied.values.map(\.position) == ["10", "11", "1"])
}
@Test func laggingFeedResumesFromAppliedCursorAndRefusalDoesNotRetry() async throws {
  let retryable = try ScriptedFeedRepository(
    batches: [[publication("10")], [publication("11")]], firstEnd: .lagging)
  let applied = AppliedCursors()
  try await MessagingService(repository: retryable).watch("chat") { await applied.append($0) }
  #expect(await retryable.requested.map { $0?.position } == [nil, "10"])
  #expect(await applied.values.map(\.position) == ["10", "11"])
  let refused = ScriptedFeedRepository(batches: [[]], firstEnd: .refused)
  await #expect(throws: ConversationFeedEnded.self) {
    try await MessagingService(repository: refused).watch("chat") { _ in
      Issue.record("Refused feed delivered")
    }
  }
  #expect(await refused.requested.count == 1)
}
@Test func customFeedCannotApplyForeignConversationAndLateRetirementIsTyped() async throws {
  let source = try ScriptedFeedRepository(batches: [[publication("1", id: "other")]])
  await #expect(throws: NessaGatewayError.self) {
    try await MessagingService(repository: source).watch("chat") { _ in
      Issue.record("Foreign publication applied")
    }
  }
  if case .unknownSubscription = GatewayFailureDTO.failure(
    code: "unknown_subscription", message: "arbitrary")
  {
  } else {
    Issue.record("Expected typed retirement, independent of diagnostic text")
  }
}
