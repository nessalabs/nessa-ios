import Testing

@testable import NessaFeatures

@Suite struct AgentsGlanceTests {
  private func chat(_ id: String, at time: Double, running: Bool = false) -> NessaConversation {
    NessaConversation(
      conversationId: id, title: id, preview: nil, updatedAtMs: time, running: running)
  }

  @Test func eachChatLandsInOneGroupNewestFirst() {
    let glance = AgentsGlance(
      conversations: [
        chat("old", at: 1), chat("asks", at: 2, running: true), chat("busy", at: 3, running: true),
        chat("done", at: 4), chat("busier", at: 5, running: true),
      ],
      waiting: ["asks"], unread: ["done", "old"])
    #expect(glance.ids(.needsYou) == ["asks"])
    #expect(glance.ids(.working) == ["busier", "busy"])
    #expect(glance.ids(.finished) == ["done", "old"])
    #expect(glance.ids(.earlier).isEmpty)
  }

  @Test func aChatNothingWaitsOnOrWorksInIsEarlier() {
    let glance = AgentsGlance(conversations: [chat("a", at: 1)], waiting: [], unread: [])
    #expect(glance.ids(.earlier) == ["a"])
  }
}

@Test @MainActor func answeringAWaitingReviewTakesTheChatOutOfNeedsYou() async throws {
  let model = MessagesViewModel(
    service: MessagingService(repository: MockRepository()), credentials: InMemoryCredentialStore(),
    preferences: InMemoryChatPreferences())
  await model.connect(address: "mock://one", credential: "", instance: "phone")
  let id = "00000000-0000-4000-8000-000000000002"
  await model.refresh(id)
  #expect(model.agentsGlance.ids(.needsYou) == [id])
  let permission = try #require(model.views[id]?.permissions.first)
  let allow = try #require(permission.options.first { $0.effect == "allow" })
  await model.answer(permission, option: allow, in: id)
  #expect(model.agentsGlance.ids(.needsYou).isEmpty)
  #expect(model.views[id]?.permissions.isEmpty == true)
}
