import Testing
@testable import NessaFeatures

@MainActor
struct ExactAgentsOverviewTests {
  @Test func reviewOnlyAcceptsAnOfferedOptionForTheRequestShown() async throws {
    let model = MessagesViewModel(service: MessagingService(repository: MockRepository()),
      credentials: InMemoryCredentialStore(), preferences: InMemoryChatPreferences())
    await model.connect(address: "mock://development", credential: "", instance: "phone")
    let id = "00000000-0000-4000-8000-000000000002"
    await model.refresh(id)
    let overview = ExactAgentsOverview(store: model)
    let groups = try #require(overview.snapshot()["groups"] as? [[String: Any]])
    let needsYou = try #require(groups.first { $0["id"] as? String == "needsYou" })
    let rows = try #require(needsYou["rows"] as? [[String: Any]])
    let row = try #require(rows.first { $0["id"] as? String == id })
    let stamp = try #require(row["reviewStamp"] as? String)
    let permission = try #require(model.waitingPermission(in: id))
    #expect(row["arguments"] as? String == permission.argumentsJson)
    let offered = try #require(row["options"] as? [[String: Any]])
    let expected = permission.options.filter { $0.effect != "allow" } + permission.options.filter { $0.effect == "allow" }
    #expect(offered.compactMap { $0["id"] as? String } == expected.map(\.id))
    let option = try #require(permission.options.first { $0.effect == "allow" })
    var request: [String: Any] = [
      "verb": "answer", "id": id, "stamp": "an older request", "option": option.id,
      "scope": model.deliveryScopeRevision, "connection": model.connectionRevision,
    ]
    _ = await overview.perform(request)
    #expect(model.waitingPermission(in: id) == permission)
    request["stamp"] = stamp
    request["option"] = "not-offered"
    _ = await overview.perform(request)
    #expect(model.waitingPermission(in: id) == permission)
    request["option"] = option.id
    _ = await overview.perform(request)
    #expect(model.waitingPermission(in: id) == nil)
  }

  @Test func staleArchiveConfirmationCannotMoveAChatOnAnotherConnection() async throws {
    let model = MessagesViewModel(service: MessagingService(repository: MockRepository()),
      credentials: InMemoryCredentialStore(), preferences: InMemoryChatPreferences())
    await model.connect(address: "mock://development", credential: "", instance: "phone")
    let chat = try #require(model.visibleConversations.first)
    let overview = ExactAgentsOverview(store: model)
    var request: [String: Any] = [
      "verb": "archive", "id": chat.id, "scope": model.deliveryScopeRevision,
      "connection": model.connectionRevision - 1,
    ]
    _ = await overview.perform(request)
    #expect(!model.archivedChats.contains(chat.id))
    request["connection"] = model.connectionRevision
    _ = await overview.perform(request)
    #expect(model.archivedChats.contains(chat.id))
  }
}
