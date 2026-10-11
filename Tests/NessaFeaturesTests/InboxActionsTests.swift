import Foundation
import Testing

@testable import NessaFeatures

@Test @MainActor func archivePersistsWithinGatewayAndUnpinsWithoutDeleting() async throws {
  let repository = MockRepository()
  let preferences = InMemoryChatPreferences()
  let model = MessagesViewModel(
    service: MessagingService(repository: repository), credentials: InMemoryCredentialStore(),
    preferences: preferences)
  await model.connect(address: "mock://one", credential: "", instance: "phone")
  let id = try #require(model.conversations.first?.id)
  model.togglePin(id)
  model.setArchived(true, conversationID: id)
  #expect(model.archivedChats == [id])
  #expect(!model.isPinned(id))
  #expect(model.conversations.contains { $0.id == id })
  await model.connect(address: "mock://one", credential: "", instance: "phone")
  #expect(model.archivedChats == [id])
  model.setArchived(false, conversationID: id)
  #expect(model.archivedChats.isEmpty)
  model.setArchived(true, conversationID: id)
  await model.connect(address: "mock://two", credential: "", instance: "phone")
  #expect(model.archivedChats.isEmpty)
}

@Test @MainActor func bulkDeleteRemovesOnlySelectedChatsAndClearsTheirArchiveAndPins() async throws
{
  let model = NessaDependencies.development().makeMessagesViewModel()
  await model.connect(address: "mock://delete", credential: "", instance: "phone")
  let ids = Set(model.conversations.prefix(2).map(\.id))
  let retained = try #require(model.conversations.last?.id)
  for id in ids {
    model.togglePin(id)
    model.setArchived(true, conversationID: id)
  }
  await model.deleteConversations(ids)
  #expect(model.conversations.count == 10)
  #expect(model.conversations.contains { $0.id == retained })
  #expect(model.archivedChats.isEmpty)
  #expect(model.pinnedChats.isEmpty)
  try await model.refreshList()
  #expect(!model.conversations.contains { ids.contains($0.id) })
}
