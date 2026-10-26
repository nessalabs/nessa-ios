import Foundation
import Testing

@testable import NessaFeatures

@Test @MainActor func archiveIsTheGatewaysAndUnpinsWithoutDeleting() async throws {
  let repository = MockRepository()
  let model = MessagesViewModel(
    service: MessagingService(repository: repository), credentials: InMemoryCredentialStore(),
    preferences: InMemoryChatPreferences())
  await model.connect(address: "mock://one", credential: "", instance: "phone")
  let id = try #require(model.conversations.first?.id)
  model.togglePin(id)
  await model.setArchived(true, conversationID: id)
  #expect(model.archivedChats == [id])
  #expect(!model.isPinned(id))
  #expect(model.conversations.contains { $0.id == id })
  // The gateway holds it archived: a fresh read of both lists agrees.
  #expect(try await repository.listArchived().conversations.map(\.id) == [id])
  #expect(!(try await repository.list().conversations.contains { $0.id == id }))
  await model.connect(address: "mock://one", credential: "", instance: "phone")
  await model.loadArchived()
  #expect(model.archivedChats == [id])
  #expect(model.conversations.contains { $0.id == id })
  await model.setArchived(false, conversationID: id)
  #expect(model.archivedChats.isEmpty)
  #expect(model.conversations.contains { $0.id == id })
  #expect(try await repository.listArchived().conversations.isEmpty)
}

@Test @MainActor func bulkDeleteRemovesOnlySelectedChatsAndClearsTheirArchiveAndPins() async throws
{
  let model = NessaDependencies.development().makeMessagesViewModel()
  await model.connect(address: "mock://delete", credential: "", instance: "phone")
  let ids = Set(model.conversations.prefix(2).map(\.id))
  let retained = try #require(model.conversations.last?.id)
  for id in ids {
    model.togglePin(id)
    await model.setArchived(true, conversationID: id)
  }
  #expect(model.archivedChats.count == 2)
  await model.deleteConversations(ids)
  #expect(model.conversations.contains { $0.id == retained })
  #expect(model.archivedChats.isEmpty)
  #expect(model.pinnedChats.isEmpty)
  try await model.refreshList()
  #expect(!model.conversations.contains { ids.contains($0.id) })
}
