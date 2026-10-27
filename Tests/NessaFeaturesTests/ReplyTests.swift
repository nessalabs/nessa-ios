import Foundation
import Testing

@testable import NessaFeatures

private func replyTurn(_ id: String, user: String, agent: String = "") -> NessaTurn {
  NessaTurn(
    executionId: id, userText: user, status: "completed", error: nil,
    parts: agent.isEmpty
      ? [] : [NessaPart(offset: 0, kind: "text", text: agent, messageId: "answer")])
}

@Test
func explicitRepliesPreserveIdentityAndGroupNestedReplies() throws {
  let first = replyTurn("first", user: "Hi", agent: "Same text")
  let duplicate = replyTurn("duplicate", user: "Again", agent: "Same text")
  let target = MessageReply(id: "first:answer:0", author: "Agent", text: "Same text")
  let second = replyTurn("second", user: target.contextualizing("My reply"), agent: "Answer")
  let nestedTarget = MessageReply(id: "second:user", author: "You", text: "My reply")
  let third = replyTurn("third", user: nestedTarget.contextualizing("Nested reply"), agent: "Done")
  let index = ConversationReplies(
    turns: [first, duplicate, second, third],
    targets: ["second": target.id, "third": nestedTarget.id], agentName: "Agent")
  let message = try #require(index.message("second:user"))
  #expect(message.summary == "My reply")
  #expect(index.parent(of: message)?.id == target.id)
  #expect(index.root(for: "third:answer:0")?.id == target.id)
  #expect(index.count(for: target.id) == 2)
  #expect(
    index.replies(to: target.id).map(\.id) == [
      "second:user", "second:answer:0", "third:user", "third:answer:0",
    ])
  #expect(index.count(for: "duplicate:answer:0") == 0)
}

@Test
func legacyRepliesMigrateOnlyWhenTheQuotedSourceIsUnambiguous() throws {
  let first = replyTurn("first", user: "Question", agent: "Line one\nLine two")
  let quoted = "> Line one\n> Line two\n\nThanks"
  let reply = replyTurn("reply", user: quoted)
  let index = ConversationReplies(turns: [first, reply], targets: [:], agentName: "Agent")
  #expect(index.message("reply:user")?.summary == "Thanks")
  #expect(index.root(for: "reply:user")?.id == "first:answer:0")
  let duplicate = replyTurn("duplicate", user: "Again", agent: "Line one\nLine two")
  let ambiguous = ConversationReplies(
    turns: [first, duplicate, reply], targets: [:], agentName: "Agent")
  #expect(ambiguous.message("reply:user")?.summary == quoted)
  #expect(ambiguous.count(for: "first:answer:0") == 0)
  #expect(MessageReply.splitContext("> Quote\nNot a quote\n\nText") == nil)
}

@Test
func attachmentRepliesUseTheSameThreadRelationships() throws {
  var first = replyTurn("first", user: "")
  first.attachments = [NessaStoredAttachment(digest: "photo", mimeType: "image/jpeg", size: 10)]
  first.files = [NessaFileAttachment(name: "Notes.txt", mimeType: "text/plain")]
  var photoReply = replyTurn("photo-reply", user: "> Photo\n\n")
  photoReply.attachments = first.attachments
  let fileReply = replyTurn("file-reply", user: "> Notes.txt\n\nLooks good")
  let index = ConversationReplies(
    turns: [first, photoReply, fileReply],
    targets: ["photo-reply": "first:photos", "file-reply": "first:file:0"], agentName: "Agent")
  #expect(index.root(for: "photo-reply:photos")?.id == "first:photos")
  #expect(index.count(for: "first:photos") == 1)
  #expect(index.message("photo-reply:user") == nil)
  #expect(index.root(for: "file-reply:user")?.id == "first:file:0")
  #expect(index.count(for: "first:file:0") == 1)
}

@Test
func invalidReplyCyclesAndMissingSourcesDoNotLoop() {
  let index = ConversationReplies(
    turns: [replyTurn("one", user: "One"), replyTurn("two", user: "Two")],
    targets: ["one": "two:user", "two": "one:user"], agentName: "Agent")
  #expect(index.messages.count == 2)
  let missing = ConversationReplies(
    turns: [replyTurn("reply", user: "> Original\n\nReply")],
    targets: ["reply": "missing:user"], agentName: "Agent")
  #expect(missing.message("reply:user")?.summary == "Reply")
  #expect(missing.root(for: "reply:user")?.summary == "Original")
  #expect(missing.count(for: "missing:user") == 1)
}

@Test @MainActor
func replyLinksPersistStayScopedAndAreRemovedWithTheConversation() async throws {
  let repository = MockRepository()
  let service = MessagingService(repository: repository)
  let preferences = InMemoryChatPreferences()
  func makeModel() -> MessagesViewModel {
    MessagesViewModel(
      service: service, credentials: InMemoryCredentialStore(), preferences: preferences)
  }
  let model = makeModel()
  await model.connect(address: "mock://reply-one", credential: "", instance: "test")
  let id = try #require(model.conversations.first?.id)
  await model.refresh(id)
  let turn = try #require(model.views[id]?.messages.first)
  let target = MessageReply(id: turn.id + ":user", author: "You", text: turn.userText)
  #expect(await model.send("A reply", reply: target, to: id))
  let sent = try #require(model.views[id]?.messages.last)
  #expect(sent.userText == target.contextualizing("A reply"))
  #expect(model.replies(in: id)[sent.id] == target.id)
  #expect(model.replyProjection(in: id).message(sent.id + ":user")?.summary == "A reply")
  let reloaded = makeModel()
  await reloaded.connect(address: "mock://reply-one", credential: "", instance: "test")
  #expect(reloaded.replies(in: id)[sent.id] == target.id)
  await reloaded.connect(address: "mock://reply-two", credential: "", instance: "test")
  #expect(reloaded.replyTargets.isEmpty)
  await model.deleteConversation(for: id)
  #expect(model.replies(in: id).isEmpty)
}

@Test
func replyContextCountsTowardTheWireLimitAndCannotSendAnEmptyDraft() async throws {
  let repository = MockRepository()
  let service = MessagingService(repository: repository)
  try await service.connect(address: "mock://reply", credential: "", instance: "test")
  let id = try await service.create(agent: nil)
  let target = MessageReply(id: "source", author: "Agent", text: String(repeating: "é", count: 600))
  #expect(target.context.utf8.count == 1002)
  await #expect(throws: NessaGatewayError.self) {
    try await service.send("", reply: target, conversationID: id)
  }
  await #expect(throws: NessaGatewayError.self) {
    try await service.send(String(repeating: "x", count: 8000), reply: target, conversationID: id)
  }
  let executionID = try await service.send("Valid", reply: target, conversationID: id)
  #expect(try await service.read(id).messages.last?.id == executionID)
}
