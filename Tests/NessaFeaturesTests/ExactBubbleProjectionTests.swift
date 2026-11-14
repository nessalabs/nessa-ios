import Foundation
import Testing
@testable import NessaFeatures

@Suite struct ExactBubbleProjectionTests {
  @Test func repeatedPhotosAndFilesUseOccurrenceIdentity() {
    let stored = NessaStoredAttachment(digest: "sha256:fixture", mimeType: "image/png", size: 42)
    var turn = NessaTurn(executionId: "turn:image:reused", userText: "", status: "completed", error: nil, parts: [])
    turn.attachments = [stored, stored]
    let file = NessaFileAttachment(name: "Review.md", mimeType: "text/markdown", data: Data([1,2]))
    turn.files = [file]
    let view = ConversationReplies(turns: [turn], targets: [:], agentName: "Nessa")
    let photo = view.messages[0]
    let row = ExactBubbleProjection.message(photo, parent: nil, replies: 0, reaction: "❤️", scope: 9)
    #expect(row["kind"] as? String == "photo")
    #expect(row["reaction"] as? String == "❤️")
    #expect(row["scope"] as? Int == 9)
    let ids = (row["photos"] as? [[String: Any]])?.compactMap { $0["id"] as? String }
    #expect(ids == ["turn:image:reused:image:0", "turn:image:reused:image:1"])
    #expect(ExactBubbleProjection.attachment("turn:image:reused:image:1", in: [turn]) == stored)
    #expect(ExactBubbleProjection.attachment("turn:image:reused:image:2", in: [turn]) == nil)
    #expect(ExactBubbleProjection.attachment("other:image:1", in: [turn]) == nil)
    let fileRow = ExactBubbleProjection.message(view.messages[1], parent: photo, replies: 2, reaction: nil, scope: 9)
    #expect(fileRow["kind"] as? String == "file")
    #expect(fileRow["text"] as? String == file.name)
    #expect(fileRow["parentID"] as? String == photo.id)
    #expect(fileRow["parentText"] as? String == "2 photos")
    #expect(fileRow["replyCount"] as? Int == 2)
  }

  @Test @MainActor func occurrenceReadsUseTheMountedChatsActualStoredImage() async throws {
    let store = MessagesViewModel(service: MessagingService(repository: MockRepository()),
      credentials: InMemoryCredentialStore(), preferences: InMemoryChatPreferences())
    await store.connect(address: "mock://development", credential: "", instance: "phone")
    let id = try #require(store.visibleConversations.first?.id)
    await store.refresh(id)
    let turns = try #require(store.views[id]?.messages)
    let first = try #require(turns.first)
    let attachment = try #require(ExactBubbleProjection.attachment(first.id + ":image:0", in: turns))
    let bytes = try #require(await store.imageData(for: attachment))
    #expect(bytes.count == attachment.size)
    #expect(await PhotoProcessing.thumbnail(bytes, maximumDimension: 32) != nil)
    #expect(ExactBubbleProjection.attachment(first.id + ":image:0", in: []) == nil)
  }
}

#if os(iOS)
extension ExactBubbleProjectionTests {
  @Test @MainActor func nativePixelViewClearsOnRebindAndScopeChange() async throws {
    let store = MessagesViewModel(service: MessagingService(repository: MockRepository()),
      credentials: InMemoryCredentialStore(), preferences: InMemoryChatPreferences())
    await store.connect(address: "mock://development", credential: "", instance: "phone")
    let id = try #require(store.visibleConversations.first?.id)
    await store.refresh(id)
    let turn = try #require(store.views[id]?.messages.first)
    var status = ""
    let photo = ExactBubblePhotoView(store: store) { status = $0 }
    var props = ["chat": id, "item": turn.id + ":image:0", "deliveryRevision": String(store.deliveryScopeRevision)]
    photo.configure(props)
    for _ in 0..<100 where status == "loading" {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(status == "ready")
    #expect(photo.image != nil)
    props["deliveryRevision"] = String(store.deliveryScopeRevision + 1)
    photo.configure(props)
    #expect(photo.image == nil)
    #expect(status == "unavailable")
    props["deliveryRevision"] = String(store.deliveryScopeRevision)
    props["item"] = "unrelated:image:0"
    photo.configure(props)
    #expect(photo.image == nil)
    #expect(status == "unavailable")
    photo.stop()
  }
}
#endif
