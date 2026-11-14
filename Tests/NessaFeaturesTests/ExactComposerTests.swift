#if os(iOS)
import Foundation
import Testing
@testable import NessaFeatures

@Suite @MainActor struct ExactComposerTests {
  private func connectedPhone() async -> ExactPhoneSession {
    let phone = ExactPhoneSession { _ in }
    await phone.messages.connect(address: "mock://development", credential: "", instance: "composer-tests")
    return phone
  }

  private func until(_ predicate: () -> Bool) async -> Bool {
    for _ in 0..<200 {
      if predicate() { return true }
      await Task.yield()
      try? await Task.sleep(for: .milliseconds(5))
    }
    return predicate()
  }

  @Test func channelCreationHandsOffOneMessageAndIgnoresCapturedLateEditing() async throws {
    let phone = await connectedPhone()
    let channel = try #require(phone.messages.channels.first { !$0.isDefault })
    var newChat = ""
    let entry = ExactComposerDraft(phone: phone, visit: "8", screen: "channel", key: channel.id,
      thread: nil, changed: {}, navigate: { newChat = String($0.dropFirst("/chat/".count)).removingPercentEncoding ?? "" })
    entry.appeared()
    defer { entry.finish() }
    await entry.perform("edit", value: "old", sequence: 1)
    await entry.perform("edit", value: "channel draft", sequence: 3)
    await entry.perform("edit", value: "late old text", sequence: 2)
    #expect(entry.draft.text == "channel draft")
    await entry.perform("send", value: "channel draft", sequence: 4)
    #expect(!newChat.isEmpty)
    #expect(phone.messages.conversations(inChannel: channel.id).contains { $0.id == newChat })
    #expect(phone.firstMessages[newChat]?.text == "channel draft")
    #expect(entry.draft.text.isEmpty)
    let threads = ExactThreads(phone: phone, changed: {})
    let handle = threads.composerHandle(newChat)
    let editor = ExactComposerDraft(phone: phone, visit: "9", screen: "chat", key: newChat,
      thread: handle, changed: {}, navigate: { _ in })
    editor.appeared()
    editor.appeared()
    defer { editor.finish() }
    #expect(await until { phone.messages.views[newChat]?.messages.contains { $0.userText == "channel draft" } == true })
    #expect(phone.messages.views[newChat]?.messages.filter { $0.userText == "channel draft" }.count == 1)
    #expect(phone.firstMessages[newChat] == nil)
  }

  @Test func filePolicyRemovalAndUnmountKeepStaleControlsFromChangingTheDraft() async throws {
    let phone = await connectedPhone()
    let editor = ExactComposerDraft(phone: phone, visit: "1", screen: "home", key: "",
      thread: nil, changed: {}, navigate: { _ in })
    editor.appeared()
    let first = DraftAttachment(name: "example.txt", mimeType: "text/plain", data: Data("one".utf8))
    editor.prepare([{ first }])
    #expect(await until { editor.draft.attachments == [first] })
    await editor.perform("edit", value: "unchanged", sequence: 1)
    let bad = DraftAttachment(name: "empty.txt", mimeType: "text/plain", data: Data())
    editor.prepare([{ bad }])
    #expect(await until { !(editor.snapshot["error"] as? String ?? "").isEmpty })
    #expect(editor.draft.attachments == [first])
    #expect(editor.draft.text == "unchanged")
    await editor.perform("clearError", value: "", sequence: 1)
    await editor.perform("remove", value: first.id.uuidString, sequence: 1)
    #expect(editor.draft.attachments.isEmpty)
    await editor.perform("dictate", value: "", sequence: 1)
    #expect(await until { editor.draft.text == "This is a mocked voice message." })
    editor.finish()
    await editor.perform("edit", value: "stale closure", sequence: 2)
    #expect(editor.draft.text == "This is a mocked voice message.")
  }
}
#endif
