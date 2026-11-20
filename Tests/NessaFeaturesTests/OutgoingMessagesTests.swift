import Foundation
import NessaNative
import Testing

@testable import NessaFeatures

@MainActor
private func connectedModel() async -> MessagesViewModel {
  let model = MessagesViewModel(
    service: MessagingService(repository: MockRepository()),
    credentials: InMemoryCredentialStore(), preferences: InMemoryChatPreferences())
  await model.connect(address: "mock://outgoing", credential: "", instance: "test")
  return model
}

/// Waits, a turn of the main actor at a time, for what a send settles into.
@MainActor
private func settle(_ done: () -> Bool) async {
  for _ in 0..<2_000 where !done() { try? await Task.sleep(for: .milliseconds(5)) }
}

@Test @MainActor
func aStartedChatShowsItsMessageAtOnceAndKeepsIt() async throws {
  let model = await connectedModel()
  let outgoing = OutgoingMessagesViewModel()
  let id = outgoing.start(
    HomeFirstMessage(text: "Hello", attachments: []), channel: nil, store: model)
  // Before anything has been made or sent, the chat already holds the message.
  #expect(outgoing.isUnmade(id))
  #expect(outgoing.messages(in: id, shown: []).map(\.text) == ["Hello"])
  #expect(outgoing.isSending(in: id))
  await settle { outgoing.messages.isEmpty }
  #expect(!outgoing.isUnmade(id))
  #expect(outgoing.messages.isEmpty)
  #expect(model.views[id]?.messages.last?.userText == "Hello")
  #expect(model.error == nil)
}

@Test @MainActor
func aRefusedSendStaysInItsChatWithItsReasonAndNoAlert() async throws {
  let model = await connectedModel()
  let outgoing = OutgoingMessagesViewModel()
  let id = try #require(await model.create())
  outgoing.send("Hi #fail", attachments: [], reply: nil, to: id, store: model)
  await settle { outgoing.messages.first?.state != .sending }
  let message = try #require(outgoing.messages.first)
  #expect(message.state == .failed("Your Mac didn’t take this message."))
  #expect(model.error == nil)
  #expect(!outgoing.isSending(in: id))
  // Tried again, it goes under a new request: the refused one stays refused.
  let refused = message.identity
  outgoing.retry(message.id, store: model)
  #expect(outgoing.messages.first?.state == .sending)
  await settle { outgoing.messages.first?.state != .sending }
  #expect(outgoing.messages.first?.identity != refused)
  #expect(outgoing.messages.count == 1)
}

@Test @MainActor
func anUnansweredSendIsTriedAgainUnderTheSameRequest() async throws {
  let model = await connectedModel()
  let outgoing = OutgoingMessagesViewModel()
  let id = try #require(await model.create())
  outgoing.send("Hi #lost", attachments: [], reply: nil, to: id, store: model)
  await settle { outgoing.messages.first?.state != .sending }
  let message = try #require(outgoing.messages.first)
  guard case .failed = message.state else { Issue.record("expected a failure"); return }
  // It may have landed, so the retry must not be a second, new send.
  outgoing.retry(message.id, store: model)
  await settle { outgoing.messages.first?.state != .sending }
  #expect(outgoing.messages.first?.identity == message.identity)
  #expect(model.error == nil)
}

@Test @MainActor
func aMessageTheTranscriptShowsIsNotDrawnTwice() async throws {
  let model = await connectedModel()
  let outgoing = OutgoingMessagesViewModel()
  let id = try #require(await model.create())
  outgoing.send("Hi #fail", attachments: [], reply: nil, to: id, store: model)
  let turn = try #require(outgoing.messages.first?.identity.executionID)
  #expect(outgoing.messages(in: id, shown: [turn]).isEmpty)
  #expect(outgoing.messages(in: "another chat", shown: []).isEmpty)
}

@Test
func nativeLinkFailuresReadAsPlainWords() {
  let cases: [any Error] = [
    NativeWorkerError.busy, NativeWorkerError.closed,
    NativeProductDeliveryFailure(id: 1, kind: .notDispatched, failure: nil),
    NativeProductDeliveryFailure(id: 2, kind: .uncertain, failure: nil),
  ]
  for error in cases {
    let words = NativeProductLinkFailure(underlying: error).localizedDescription
    #expect(!words.contains("Native"))
    #expect(!words.contains("("))
  }
  #expect(
    NativeProductLinkFailure.sentence(.timedOut) == "Your Mac didn’t answer in time. Try again.")
  #expect(NativeProductLinkFailure.sentence(.transport) == "Can’t reach your Mac right now.")
}

@Test
func cancellationAndGatewayErrorsPassThroughUnworded() async {
  await #expect(throws: CancellationError.self) {
    try await NativeProductLinkFailure.worded { () async throws -> Int in throw CancellationError() }
  }
  await #expect(throws: NessaGatewayError.timeout) {
    try await NativeProductLinkFailure.worded { () async throws -> Int in
      throw NessaGatewayError.timeout
    }
  }
}

@Test @MainActor
func aChatThatCouldNotBeMadeHandsItsMessageBackOnceNobodyIsLooking() async throws {
  // Never connected, so the chat can't be made.
  let model = MessagesViewModel(
    service: MessagingService(repository: MockRepository()),
    credentials: InMemoryCredentialStore(), preferences: InMemoryChatPreferences())
  let outgoing = OutgoingMessagesViewModel()
  let id = outgoing.start(
    HomeFirstMessage(text: "Hello", attachments: []), channel: nil, store: model)
  outgoing.onScreen(id, true)
  await settle { outgoing.messages.first?.state != .sending }
  // While its chat is on screen the message stays there, marked unsent.
  #expect(outgoing.messages.count == 1)
  #expect(outgoing.takeReturned(channel: nil) == nil)
  outgoing.onScreen(id, false)
  #expect(outgoing.messages.isEmpty)
  #expect(!outgoing.isUnmade(id))
  #expect(outgoing.takeReturned(channel: nil)?.text == "Hello")
  #expect(outgoing.takeReturned(channel: nil) == nil)
}
