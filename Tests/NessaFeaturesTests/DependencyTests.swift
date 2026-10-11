import Foundation
import Testing

@testable import NessaFeatures

@Test @MainActor
func mockInjectionSupportsChatLifecycleAndKeepsInstancesIsolated() async throws {
  let dependencies = NessaDependencies.development()
  let model = dependencies.makeMessagesViewModel()
  await model.connect(address: "mock://development", credential: "", instance: "test")
  #expect(model.connected)
  #expect(model.conversations.count == 12)
  let id = try #require(await model.create())
  let attachment = DraftAttachment(
    name: "notes.txt", mimeType: "text/plain", data: Data("notes".utf8))
  #expect(await model.send("Remember this", attachments: [attachment], to: id))
  #expect(model.views[id]?.messages.last?.userText.contains("notes.txt") == true)
  model.togglePin(id)
  #expect(model.isPinned(id))
  let second = NessaDependencies.development().makeMessagesViewModel()
  await second.connect(address: "mock://development", credential: "", instance: "test")
  #expect(second.pinnedChats.isEmpty)
  #expect(!second.conversations.contains { $0.id == id })
  await model.deleteConversation(for: id)
  #expect(!model.conversations.contains { $0.id == id })
  #expect(!model.isPinned(id))
}

@Test
func applicationRejectsInvalidInputAndAllowsAttachmentOnlyMessages() async throws {
  let repository = MockRepository()
  let service = MessagingService(repository: repository)
  try await service.connect(address: "mock://development", credential: "", instance: "test")
  let id = try await service.create(agent: nil)
  await #expect(throws: NessaGatewayError.self) { try await service.send(" ", conversationID: id) }
  await #expect(throws: NessaGatewayError.self) {
    try await service.send(String(repeating: "é", count: 4097), conversationID: id)
  }
  let attachment = DraftAttachment(
    name: "photo.jpg", mimeType: "image/jpeg", data: Data([1, 2, 3]))
  try await service.send("", attachments: [attachment], conversationID: id)
  let thread = try await service.read(id)
  #expect(thread.messages.count == 1)
  #expect(thread.messages.first?.attachments?.count == 1)
}

@Test @MainActor
func externalAgentIdentityIsIndependentOfNessaTransport() async throws {
  let agent = AgentProfile(id: "external-agent-42", displayName: "Research companion")
  let repository = MockRepository(agents: [agent])
  let model = NessaDependencies.development(repository: repository).makeMessagesViewModel()
  await model.connect(address: "mock://external", credential: "", instance: "test")
  let id = try #require(await model.create(agent: agent.id))
  #expect(model.agentName(for: id) == "Research companion")
  model.togglePin(id)
  #expect(model.isPinned(id))
  #expect(await model.send("Hello", to: id))
}

@Test @MainActor
func reactionsTogglePersistAndStayScopedToConnection() async throws {
  let repository = MockRepository()
  let preferences = InMemoryChatPreferences()
  let service = MessagingService(repository: repository)
  let model = MessagesViewModel(
    service: service, credentials: InMemoryCredentialStore(), preferences: preferences)
  await model.connect(address: "mock://one", credential: "", instance: "test")
  let id = try #require(await model.create())
  #expect(model.conversations.contains { $0.id == id })
  model.react("❤️", message: "message-1", in: id)
  #expect(model.reaction(message: "message-1", in: id) == "❤️")
  let second = MessagesViewModel(
    service: service, credentials: InMemoryCredentialStore(), preferences: preferences)
  await second.connect(address: "mock://one", credential: "", instance: "test")
  #expect(second.reaction(message: "message-1", in: id) == "❤️")
  second.react("❤️", message: "message-1", in: id)
  #expect(second.reaction(message: "message-1", in: id) == nil)
  await model.connect(address: "mock://two", credential: "", instance: "test")
  #expect(model.reaction(message: "message-1", in: id) == nil)
}
