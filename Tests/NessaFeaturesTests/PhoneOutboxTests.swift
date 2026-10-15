import Foundation
import Testing

@testable import NessaFeatures

actor MemoryOutboxStore: PhoneOutboxStoring {
  private var records: [PhoneOutboxRecord] = []
  func load(_ id: String) async throws -> PhoneOutboxRecord? {
    records.first { $0.intent.commandID == id }
  }
  func insert(_ record: PhoneOutboxRecord) async throws {
    guard !records.contains(where: { $0.intent.commandID == record.intent.commandID }) else {
      throw PhoneOutboxStoreFailure.conflict
    }
    records.append(record)
  }
  func replace(_ previous: PhoneOutboxRecord, with next: PhoneOutboxRecord) async throws {
    guard let index = records.firstIndex(where: { $0 == previous }) else {
      throw PhoneOutboxStoreFailure.conflict
    }
    records[index] = next
  }
  func replaceAndInsert(
    previous: PhoneOutboxRecord, next: PhoneOutboxRecord, draft: PhoneOutboxRecord
  ) async throws {
    guard let index = records.firstIndex(where: { $0 == previous }) else {
      throw PhoneOutboxStoreFailure.conflict
    }
    records[index] = next
    records.append(draft)
  }
  func list() async throws -> [PhoneOutboxRecord] { records }
}

final class ScriptedGateway: PhoneProductTransport, @unchecked Sendable {
  let store: MemoryOutboxStore
  var sendAnswers: [PhoneSendAnswer]
  var lookupAnswers: [PhoneLookupAnswer]
  var sends = 0
  var lookups = 0
  var stops = 0
  var stopLookups = 0
  var uploads = 0
  var departedBeforeSend = false
  var stopRequestIDs: [String] = []
  var stopAnswers: [PhoneSendAnswer] = []
  var stopLookupAnswers: [PhoneLookupAnswer] = []
  init(
    store: MemoryOutboxStore, sendAnswers: [PhoneSendAnswer] = [],
    lookupAnswers: [PhoneLookupAnswer] = []
  ) {
    self.store = store
    self.sendAnswers = sendAnswers
    self.lookupAnswers = lookupAnswers
  }
  func send(_ intent: PhoneSendIntent) async -> PhoneSendAnswer {
    sends += 1
    if let row = try? await store.load(intent.commandID) { departedBeforeSend = row.departed }
    return sendAnswers.isEmpty ? .lost : sendAnswers.removeFirst()
  }
  func lookup(_ intent: PhoneSendIntent) async -> PhoneLookupAnswer {
    lookups += 1
    return lookupAnswers.isEmpty ? .lost : lookupAnswers.removeFirst()
  }
  func uploadPhoneImage(_ attachment: DraftAttachment, conversationID: String) async throws
    -> NessaImageAttachment
  {
    uploads += 1
    return NessaImageAttachment(
      digest: "sha256:" + String(repeating: "ab", count: 32), mimeType: attachment.mimeType,
      size: attachment.data.count)
  }
  func phoneStop(conversationID: String, requestID: String, executionID: String) async
    -> PhoneSendAnswer
  {
    stops += 1
    stopRequestIDs.append(requestID)
    return stopAnswers.isEmpty ? .receipt(.settled) : stopAnswers.removeFirst()
  }
  func phoneLookupStop(conversationID: String, requestID: String, executionID: String) async
    -> PhoneLookupAnswer
  {
    stopLookups += 1
    return stopLookupAnswers.isEmpty
      ? .found(stage: "settled", effect: "cancelled") : stopLookupAnswers.removeFirst()
  }
}

private func intent(
  _ command: String = "11111111-1111-4111-8111-111111111111",
  turn: String = "22222222-2222-4222-8222-222222222222",
  text: String = "Hello",
  images: [NessaImageAttachment] = []
) throws -> PhoneSendIntent {
  try PhoneSendIntent(
    conversationID: "00000000-0000-4000-8000-0000000000aa", commandID: command, turnID: turn,
    text: text, images: images)
}

@Test func aSavedDraftIsNotASubmission() async throws {
  let store = MemoryOutboxStore()
  let gateway = ScriptedGateway(store: store)
  let outbox = PhoneOutbox(store: store, gateway: gateway)
  let view = try await outbox.hold(intent())
  #expect(view.outcome == .draft)
  #expect(!view.outcome.claimsSubmission)
  #expect(gateway.sends == 0)
}

@Test func aDraftSurvivesReopenWithoutASend() async throws {
  let store = MemoryOutboxStore()
  let gateway = ScriptedGateway(store: store)
  _ = try await PhoneOutbox(store: store, gateway: gateway).hold(intent())
  let reopened = PhoneOutbox(store: store, gateway: gateway)
  let recovered = try await reopened.recover()
  #expect(recovered.isEmpty)
  #expect(gateway.sends == 0 && gateway.lookups == 0)
  #expect(try await reopened.list().map(\.outcome) == [.draft])
}

@Test func aChangedBodyUnderTheSameCommandIsRefused() async throws {
  let store = MemoryOutboxStore()
  let gateway = ScriptedGateway(store: store)
  let outbox = PhoneOutbox(store: store, gateway: gateway)
  _ = try await outbox.hold(intent())
  await #expect(throws: PhoneOutboxFailure.conflict) {
    try await outbox.hold(intent(text: "Different"))
  }
  #expect(gateway.sends == 0)
  #expect(try await outbox.list().first?.text == "Hello")
}

@Test func departureIsDurableBeforeTheGatewayIsAsked() async throws {
  let store = MemoryOutboxStore()
  let gateway = ScriptedGateway(store: store, sendAnswers: [.receipt(.queued)])
  let outbox = PhoneOutbox(store: store, gateway: gateway)
  _ = try await outbox.hold(intent())
  let view = try await outbox.send("11111111-1111-4111-8111-111111111111")
  #expect(gateway.departedBeforeSend)
  #expect(view.outcome == .accepted)
  #expect(gateway.sends == 1)
}

@Test func aSecondSendDoesNotDuplicateAQueuedCommand() async throws {
  let store = MemoryOutboxStore()
  let gateway = ScriptedGateway(store: store, sendAnswers: [.receipt(.queued)])
  let outbox = PhoneOutbox(store: store, gateway: gateway)
  _ = try await outbox.hold(intent())
  _ = try await outbox.send("11111111-1111-4111-8111-111111111111")
  let again = try await outbox.send("11111111-1111-4111-8111-111111111111")
  #expect(again.outcome == .accepted)
  #expect(gateway.sends == 1 && gateway.lookups == 0)
}

@Test func recoveryDoesNotSendWhenTheReceiptIsAbsent() async throws {
  let store = MemoryOutboxStore()
  let gateway = ScriptedGateway(
    store: store, sendAnswers: [.lost], lookupAnswers: [.notFound, .notFound])
  let outbox = PhoneOutbox(store: store, gateway: gateway)
  _ = try await outbox.hold(intent())
  _ = try await outbox.send("11111111-1111-4111-8111-111111111111")
  let sendsBeforeReopen = gateway.sends
  let reopened = PhoneOutbox(store: store, gateway: gateway)
  let recovered = try await reopened.recover()
  #expect(recovered.first?.outcome == .unknown(.notAdmitted))
  #expect(gateway.sends == sendsBeforeReopen)
  #expect(gateway.lookups >= 1)
}

@Test func anExplicitRetryLooksUpBeforeItSends() async throws {
  let store = MemoryOutboxStore()
  let gateway = ScriptedGateway(
    store: store, sendAnswers: [.lost, .receipt(.queued)],
    lookupAnswers: [.notFound, .notFound])
  let outbox = PhoneOutbox(store: store, gateway: gateway)
  _ = try await outbox.hold(intent())
  _ = try await outbox.send("11111111-1111-4111-8111-111111111111")
  let sends = gateway.sends
  let retried = try await outbox.retry("11111111-1111-4111-8111-111111111111")
  #expect(retried.outcome == .accepted)
  #expect(gateway.sends == sends + 1)
}

@Test func anExplicitRetryDoesNotSendAFinishedCommand() async throws {
  let store = MemoryOutboxStore()
  let gateway = ScriptedGateway(store: store, sendAnswers: [.receipt(.settled)])
  let outbox = PhoneOutbox(store: store, gateway: gateway)
  _ = try await outbox.hold(intent())
  _ = try await outbox.send("11111111-1111-4111-8111-111111111111")
  let retried = try await outbox.retry("11111111-1111-4111-8111-111111111111")
  #expect(retried.outcome == .done)
  #expect(gateway.sends == 1 && gateway.lookups == 0)
}

@Test func turnRunningReturnsTheTextToANewDraft() async throws {
  let store = MemoryOutboxStore()
  let gateway = ScriptedGateway(store: store, sendAnswers: [.refused("turn_running")])
  let outbox = PhoneOutbox(store: store, gateway: gateway)
  _ = try await outbox.hold(intent())
  let failed = try await outbox.send("11111111-1111-4111-8111-111111111111")
  #expect(failed.outcome == .failed("turn_running"))
  let rows = try await outbox.list()
  #expect(rows.contains { $0.outcome == .draft && $0.text == "Hello" && $0.commandID != failed.commandID })
  _ = try await outbox.send(failed.commandID)
  #expect(gateway.sends == 1)
}

@Test func aLostAnswerRetransmitsUntilTheBound() async throws {
  let store = MemoryOutboxStore()
  let gateway = ScriptedGateway(
    store: store, sendAnswers: Array(repeating: .lost, count: 5),
    lookupAnswers: Array(repeating: .notFound, count: 5))
  let outbox = PhoneOutbox(store: store, gateway: gateway)
  _ = try await outbox.hold(intent())
  let view = try await outbox.send("11111111-1111-4111-8111-111111111111")
  #expect(view.outcome == .unknown(.notAdmitted))
  #expect(gateway.sends == phoneForegroundSends)
}

@Test func aRefusalIsFailedAndNotSentAgain() async throws {
  let store = MemoryOutboxStore()
  let gateway = ScriptedGateway(store: store, sendAnswers: [.refused("forbidden")])
  let outbox = PhoneOutbox(store: store, gateway: gateway)
  _ = try await outbox.hold(intent())
  let view = try await outbox.send("11111111-1111-4111-8111-111111111111")
  #expect(view.outcome == .failed("forbidden"))
  _ = try await outbox.send(view.commandID)
  #expect(gateway.sends == 1)
}

@Test func anImageSendKeepsTheUploadedReference() async throws {
  let image = NessaImageAttachment(
    digest: "sha256:" + String(repeating: "cd", count: 32), mimeType: "image/png", size: 4)
  let store = MemoryOutboxStore()
  let gateway = ScriptedGateway(store: store, sendAnswers: [.receipt(.queued)])
  let outbox = PhoneOutbox(store: store, gateway: gateway)
  _ = try await outbox.hold(intent(text: "", images: [image]))
  let view = try await outbox.send("11111111-1111-4111-8111-111111111111")
  #expect(view.outcome == .accepted)
  #expect(view.images == [image])
}

@Test func theFileOutboxSurvivesReopenWithoutSendingAgain() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let gateway = ScriptedGateway(
    store: MemoryOutboxStore(), sendAnswers: [.lost], lookupAnswers: [.notFound, .notFound])
  let first = PhoneOutbox(store: PhoneOutboxFileStore(directory: directory), gateway: gateway)
  _ = try await first.hold(intent())
  _ = try await first.send("11111111-1111-4111-8111-111111111111")
  let sends = gateway.sends
  let second = PhoneOutbox(store: PhoneOutboxFileStore(directory: directory), gateway: gateway)
  let recovered = try await second.recover()
  #expect(recovered.first?.outcome == .unknown(.notAdmitted))
  #expect(gateway.sends == sends)
}

@Test func stopLooksUpAfterRestartAndDoesNotStopAgain() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let gateway = ScriptedGateway(store: MemoryOutboxStore(), sendAnswers: [.receipt(.settled)])
  gateway.sendAnswers = []
  let stops = PhoneStopFileStore(directory: directory)
  let chat = PhoneProductChat(
    outbox: PhoneOutbox(store: PhoneOutboxFileStore(directory: directory), gateway: gateway),
    transport: gateway, stops: stops)
  let first = try await chat.stop(
    conversationID: "00000000-0000-4000-8000-0000000000aa",
    executionID: "22222222-2222-4222-8222-222222222222")
  #expect(first == .done)
  #expect(gateway.stops == 1 && gateway.stopLookups == 0)
  let again = try await chat.stop(
    conversationID: "00000000-0000-4000-8000-0000000000aa",
    executionID: "22222222-2222-4222-8222-222222222222")
  #expect(again == .done)
  #expect(gateway.stops == 1 && gateway.stopLookups == 0)
  try await stops.save([
    PhoneStopRecord(
      conversationID: "00000000-0000-4000-8000-0000000000aa",
      requestID: "33333333-3333-4333-8333-333333333333",
      executionID: "44444444-4444-4444-8444-444444444444", departed: true,
      outcome: .unknown(.notAdmitted))
  ])
  _ = try await chat.recover()
  #expect(gateway.stops == 1)
  #expect(gateway.stopLookups == 1)
}

@Test func anExplicitStopSendsAgainWhenTheReceiptIsAbsent() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let gateway = ScriptedGateway(store: MemoryOutboxStore())
  gateway.stopLookupAnswers = [.notFound]
  gateway.stopAnswers = [.receipt(.settled)]
  let stops = PhoneStopFileStore(directory: directory)
  let requestID = "33333333-3333-4333-8333-333333333333"
  try await stops.save([
    PhoneStopRecord(
      conversationID: "00000000-0000-4000-8000-0000000000aa",
      requestID: requestID,
      executionID: "44444444-4444-4444-8444-444444444444", departed: true,
      outcome: .unknown(.notAdmitted))
  ])
  let chat = PhoneProductChat(
    outbox: PhoneOutbox(store: PhoneOutboxFileStore(directory: directory), gateway: gateway),
    transport: gateway, stops: stops)
  let outcome = try await chat.stop(
    conversationID: "00000000-0000-4000-8000-0000000000aa",
    executionID: "44444444-4444-4444-8444-444444444444")
  #expect(outcome == .done)
  #expect(gateway.stopLookups == 1)
  #expect(gateway.stops == 1)
  #expect(gateway.stopRequestIDs == [requestID])
  _ = try await chat.recover()
  #expect(gateway.stops == 1)
}

@Test func aFailedLookupCanBeRetried() {
  #expect(PhoneSendOutcome.unknown(.lookupFailed).admitsRetry)
  #expect(PhoneSendOutcome.unknown(.notAdmitted).admitsRetry)
  #expect(!PhoneSendOutcome.unknown(.attempted).admitsRetry)
  #expect(!PhoneSendOutcome.unknown(.unresolved).admitsRetry)
  #expect(!PhoneSendOutcome.failed("forbidden").admitsRetry)
}

@Test func aConversationRefusalKeepsItsCode() {
  let error = PhoneSocketRefusal.error(code: "turn_running", message: "busy", details: nil)
  #expect((error as? GatewayProductRejection)?.code == "turn_running")
  let unresolved = PhoneSocketRefusal.error(
    code: "submission_unresolved", message: "unknown", details: nil)
  #expect((unresolved as? GatewayProductRejection)?.code == "submission_unresolved")
  #expect(PhoneSocketRefusal.error(code: nil, message: "no", details: nil) is NessaGatewayError)
}

@Test func revocationIsNotRetried() {
  #expect(GatewayFailureDTO.failure(code: "forbidden", message: "no") == .revoked("forbidden"))
  #expect(!ConnectionRecovery.retryable(NessaGatewayError.revoked("forbidden")))
  #expect(!ConnectionRecovery.retryable(NessaGatewayError.revoked("credential_revoked")))
  #expect(ConnectionRecovery.retryable(NessaGatewayError.disconnected))
}

@Test func emptyChatsStayVisible() throws {
  let empty = NessaConversation(
    conversationId: "00000000-0000-4000-8000-0000000000aa", title: nil, preview: nil,
    updatedAtMs: 1, running: false)
  let list = NessaConversationList(conversations: [empty], complete: true)
  #expect(PhoneProductChat.visible(list, hiding: []).map(\.id) == [empty.id])
  #expect(PhoneProductChat.visible(list, hiding: []).first?.title == nil)
  #expect(PhoneProductChat.visible(list, hiding: []).first?.preview == nil)
}
