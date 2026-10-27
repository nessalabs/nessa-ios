import Foundation
import Testing

@testable import NessaFeatures

private func uploadedFile(name: String = "report.pdf", size: Int = 12) -> NessaUploadedFile {
  .init(
    digest: "sha256:" + String(repeating: "a", count: 64), mimeType: "application/pdf", size: size,
    name: name)
}
@Test func bothDurableSendRepresentationsRoundTripAFileOnlyMessage() throws {
  let file = uploadedFile()
  let intent = try PhoneSendIntent(
    conversationID: "00000000-0000-4000-8000-000000000001",
    commandID: "00000000-0000-4000-8000-000000000002",
    turnID: "00000000-0000-4000-8000-000000000003", text: "", images: [], uploads: [file])
  let recovered = try JSONDecoder().decode(PhoneSendIntent.self, from: JSONEncoder().encode(intent))
  #expect(recovered == intent)
  #expect(recovered.canonical == intent.canonical)
  let command = PreparedConversationCommand.submit(
    .init(
      requestID: intent.commandID, conversationID: intent.conversationID,
      executionID: intent.turnID, text: "", uploads: [file]))
  try command.validate()
  let next = try JSONDecoder().decode(
    PreparedConversationCommand.self, from: JSONEncoder().encode(command))
  try next.validate()
  #expect(next == command)
  let changed = try PhoneSendIntent(
    conversationID: intent.conversationID, commandID: intent.commandID, turnID: intent.turnID,
    text: "", images: [], uploads: [uploadedFile(name: "different.pdf")])
  #expect(changed.canonical != intent.canonical)
}
@Test func fileReferenceBoundsRejectUnsafeNamesAndCorruptSizesBeforeTheyCanOverflow() {
  for name in ["", " ", "../escape", "dir\\file", "a\n.txt", String(repeating: "é", count: 128)] {
    #expect(!AttachmentReferences.valid(images: [], uploads: [uploadedFile(name: name)]))
  }
  for size in [0, -1, Int.max, AttachmentReferences.maximumFileBytes + 1] {
    #expect(!AttachmentReferences.valid(images: [], uploads: [uploadedFile(size: size)]))
  }
  #expect(
    AttachmentReferences.valid(
      images: [], uploads: [uploadedFile(size: AttachmentReferences.maximumFileBytes)]))
  #expect(
    !AttachmentReferences.valid(
      images: [],
      uploads: [uploadedFile(size: AttachmentReferences.maximumFileBytes), uploadedFile(size: 1)]))
}
@Test func uploadedFilesRemainVisibleInMessagesAndTheArtifactBrowserAfterDecoding() throws {
  var turn = NessaTurn(
    executionId: "turn", userText: "", status: "completed", error: nil, parts: [])
  turn.uploads = [uploadedFile()]
  let restored = try JSONDecoder().decode(NessaTurn.self, from: JSONEncoder().encode(turn))
  let messages = ConversationReplies(turns: [restored], targets: [:], agentName: "Agent").messages
  #expect(messages.count == 1)
  #expect(messages[0].summary == "report.pdf")
  #expect(ConversationArtifact.collect(from: [restored]).count == 1)
}
@Test func thePhoneOutboxKeepsUploadedReferencesWhenAnAnswerIsLost() async throws {
  let store = MemoryOutboxStore()
  let gateway = ScriptedGateway(
    store: store, sendAnswers: [.lost],
    lookupAnswers: [.lost, .found(stage: "settled", effect: "dispatched")])
  let chat = PhoneProductChat(
    outbox: PhoneOutbox(store: store, gateway: gateway), transport: gateway, stops: FileStopStore())
  let identity = MessageCommandIdentity()
  _ = try await chat.deliver(
    text: "",
    attachments: [.init(name: "report.pdf", mimeType: "application/pdf", data: Data([1, 2, 3]))],
    conversationID: "00000000-0000-4000-8000-000000000001", identity: identity, scope: nil)
  let saved = try #require(await store.load(identity.requestID))
  #expect(saved.intent.uploads.first?.name == "report.pdf")
  #expect(saved.intent.images.isEmpty)
  let outbox = PhoneOutbox(store: store, gateway: gateway)
  _ = try await outbox.recover()
  #expect(try await outbox.list().first?.outcome == .done)
  #expect(gateway.sends == 1)
}

private actor FileStopStore: PhoneStopStoring {
  private var records: [PhoneStopRecord] = []
  func load() -> [PhoneStopRecord] { records }
  func save(_ records: [PhoneStopRecord]) { self.records = records }
}

@Test func developmentRetainsItsLargerImageBudget() throws {
  let image = DraftAttachment(
    name: "large.png", mimeType: "image/png", data: Data(repeating: 0, count: 6 * 1024 * 1024))
  try AttachmentPolicy.development.validate([image])
  #expect(throws: (any Error).self) { try AttachmentPolicy.nessa.validate([image]) }
  #expect(AttachmentReferences.valid(images: [], uploads: [uploadedFile(name: "\u{FEFF}")]))
}
