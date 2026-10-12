import Testing

@testable import NessaFeatures

private actor DeleteGateRepository: MessagingRepository {
  private let repository = MockRepository()
  private var deletion: CheckedContinuation<Void, Error>?
  private var waiter: CheckedContinuation<Void, Never>?
  func connect(address: String, credential: String, instance: String) async {
    await repository.connect(address: address, credential: credential, instance: instance)
  }
  func disconnect() async { await repository.disconnect() }
  func list() async throws -> NessaConversationList { try await repository.list() }
  func read(_ id: String) async throws -> NessaConversationView { try await repository.read(id) }
  func create(agent: String?, model: String?) async throws -> String { try await repository.create(agent: agent, model: model) }
  func send(_ text: String, attachments: [DraftAttachment], conversationID: String) async throws
    -> String
  {
    try await repository.send(text, attachments: attachments, conversationID: conversationID)
  }
  func answer(_ permission: NessaPermission, option: NessaPermission.Option, conversationID: String)
    async throws
  {
    try await repository.answer(permission, option: option, conversationID: conversationID)
  }
  func delete(_ id: String) async throws {
    try await withCheckedThrowingContinuation { continuation in
      deletion = continuation
      waiter?.resume()
      waiter = nil
    }
    try await repository.delete(id)
  }
  func waitForDelete() async {
    if deletion != nil { return }
    await withCheckedContinuation { waiter = $0 }
  }
  func finish(_ result: Result<Void, Error>) {
    deletion?.resume(with: result)
    deletion = nil
  }
  func commitThenReject(_ id: String) async throws {
    try await repository.delete(id)
    finish(.failure(NessaGatewayError.rejected("Cleanup acknowledgement unavailable")))
  }
}

@Test @MainActor func failedAcknowledgementDoesNotRestoreAnAuthoritativelyDeletedChat() async throws
{
  let repository = DeleteGateRepository()
  let model = MessagesViewModel(
    service: MessagingService(repository: repository), credentials: InMemoryCredentialStore(),
    preferences: InMemoryChatPreferences())
  await model.connect(address: "mock://committed-delete", credential: "", instance: "test")
  let id = try #require(model.conversations.first?.id)
  model.togglePin(id)
  let deletion = Task { await model.deleteConversation(for: id) }
  await repository.waitForDelete()
  try await repository.commitThenReject(id)
  await deletion.value
  #expect(!model.visibleConversations.contains { $0.id == id })
  #expect(!model.isPinned(id))
  #expect(model.pendingDeletionIDs.isEmpty)
  #expect(model.error != nil)
}

@Test @MainActor func pendingDeleteHidesImmediatelySurvivesRefreshAndRestoresOnFailure()
  async throws
{
  let repository = DeleteGateRepository()
  let model = MessagesViewModel(
    service: MessagingService(repository: repository), credentials: InMemoryCredentialStore(),
    preferences: InMemoryChatPreferences())
  await model.connect(address: "mock://delete", credential: "", instance: "test")
  let id = try #require(model.conversations.first?.id)
  model.togglePin(id)
  let deletion = Task { await model.deleteConversation(for: id) }
  await repository.waitForDelete()
  #expect(model.isDeleting(id))
  #expect(!model.visibleConversations.contains { $0.id == id })
  try await model.refreshList()
  #expect(!model.visibleConversations.contains { $0.id == id })
  await repository.finish(.failure(NessaGatewayError.rejected("Test rejection")))
  await deletion.value
  #expect(model.visibleConversations.contains { $0.id == id })
  #expect(model.isPinned(id))
  #expect(model.pendingDeletionIDs.isEmpty)
  #expect(model.error != nil)
}

@Test @MainActor func bulkDeleteHidesAllTargetsBeforeFirstAcknowledgement() async throws {
  let repository = DeleteGateRepository()
  let model = MessagesViewModel(
    service: MessagingService(repository: repository), credentials: InMemoryCredentialStore(),
    preferences: InMemoryChatPreferences())
  await model.connect(address: "mock://bulk-delete", credential: "", instance: "test")
  let ids = Set(model.conversations.prefix(2).map(\.id))
  let deletion = Task { await model.deleteConversations(ids) }
  await repository.waitForDelete()
  #expect(model.visibleConversations.count == 10)
  #expect(model.pendingDeletionIDs == ids)
  await repository.finish(.success(()))
  await repository.waitForDelete()
  #expect(model.visibleConversations.count == 10)
  await repository.finish(.success(()))
  await deletion.value
  #expect(model.pendingDeletionIDs.isEmpty)
  #expect(model.conversations.count == 10)
}

@Test @MainActor func oldDeletionCannotHideChatsOnNewConnection() async throws {
  let repository = DeleteGateRepository()
  let model = MessagesViewModel(
    service: MessagingService(repository: repository), credentials: InMemoryCredentialStore(),
    preferences: InMemoryChatPreferences())
  await model.connect(address: "mock://old", credential: "", instance: "test")
  let id = try #require(model.conversations.first?.id)
  let deletion = Task { await model.deleteConversation(for: id) }
  await repository.waitForDelete()
  await model.connect(address: "mock://new", credential: "", instance: "test")
  #expect(model.pendingDeletionIDs.isEmpty)
  await repository.finish(.success(()))
  await deletion.value
  #expect(model.visibleConversations.contains { $0.id == id })
}
