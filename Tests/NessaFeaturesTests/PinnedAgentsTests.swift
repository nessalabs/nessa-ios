import Foundation
import Testing

@testable import NessaFeatures

private actor FixtureGateway: MessagingRepository, AgentDirectory {
  var creations = 0
  func connect(address: String, credential: String, instance: String) {}
  func list() throws -> NessaConversationList {
    try decode(#"{"conversations":[],"complete":true}"#)
  }
  func agents() throws -> [AgentProfile] { [AgentProfile(id: "codex", displayName: "Codex")] }
  func read(_ id: String) throws -> NessaConversationView {
    try decode(
      "{\"conversationId\":\"\(id)\",\"messages\":[],\"permissions\":[],\"truncated\":false}")
  }
  func create(agent: String?) -> String {
    creations += 1
    return "thread-\(creations)"
  }
  func send(_ text: String, attachments: [DraftAttachment], conversationID: String) {}
  func answer(_ permission: NessaPermission, option: NessaPermission.Option, conversationID: String)
  {}
  func delete(_ conversationID: String) {}
  func disconnect() {}
  private func decode<T: Decodable>(_ json: String) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(json.utf8))
  }
}
private struct FixtureCredentials: NessaCredentialStoring {
  func load() -> String? { "fixture" }
  func save(_ credential: String) {}
}

@Test @MainActor
func pinsPersistAndStayScopedToGateway() async throws {
  let suite = "nessa-test-\(UUID())"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let gateway = FixtureGateway()
  let store = MessagesViewModel(
    service: MessagingService(repository: gateway), credentials: FixtureCredentials(),
    preferences: UserDefaultsChatPreferences(defaults))
  await store.connect(address: "wss://one/session", credential: "fixture", instance: "phone")
  store.togglePin("codex")
  #expect(store.pinnedChats == ["codex"])
  let reloaded = MessagesViewModel(
    service: MessagingService(repository: gateway), credentials: FixtureCredentials(),
    preferences: UserDefaultsChatPreferences(defaults))
  await reloaded.connect(address: "wss://one/session", credential: "fixture", instance: "phone")
  #expect(reloaded.isPinned("codex"))
  await reloaded.connect(address: "wss://two/session", credential: "fixture", instance: "phone")
  #expect(reloaded.pinnedChats.isEmpty)
  store.togglePin("codex")
  #expect(store.pinnedChats.isEmpty)
}

@Test @MainActor
func openingPinnedAgentReusesItsConversation() async throws {
  let suite = "nessa-test-\(UUID())"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let gateway = FixtureGateway()
  let store = MessagesViewModel(
    service: MessagingService(repository: gateway), credentials: FixtureCredentials(),
    preferences: UserDefaultsChatPreferences(defaults))
  await store.connect(address: "wss://one/session", credential: "fixture", instance: "phone")
  let first = await store.openAgent("codex")
  let second = await store.openAgent("codex")
  #expect(first == second)
  #expect(await gateway.creations == 1)
  #expect(store.agentID(for: try #require(first)) == "codex")
}

@Test @MainActor
func previewDoesNotCreateAndConversationActionsPersist() async throws {
  let suite = "nessa-test-\(UUID())"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  let gateway = FixtureGateway()
  let store = MessagesViewModel(
    service: MessagingService(repository: gateway), credentials: FixtureCredentials(),
    preferences: UserDefaultsChatPreferences(defaults))
  await store.connect(address: "wss://one/session", credential: "fixture", instance: "phone")
  await store.loadPreview("codex")
  #expect(await gateway.creations == 0)
  store.togglePin("codex")
  _ = await store.openAgent("codex")
  store.markUnread("codex")
  store.toggleAlerts("codex")
  let reloaded = MessagesViewModel(
    service: MessagingService(repository: gateway), credentials: FixtureCredentials(),
    preferences: UserDefaultsChatPreferences(defaults))
  await reloaded.connect(address: "wss://one/session", credential: "fixture", instance: "phone")
  #expect(reloaded.unreadChats == ["codex"])
  #expect(reloaded.mutedChats == ["codex"])
  await reloaded.loadPreview("codex")
  #expect(reloaded.agentPreviews["codex"] != nil)
  _ = await reloaded.openAgent("codex")
  #expect(reloaded.unreadChats.isEmpty)
  await reloaded.deleteConversation(for: "codex")
  #expect(!reloaded.hasConversation("codex"))
  #expect(!reloaded.isPinned("codex"))
}

@Test @MainActor
func pinLimitAppliesToNewPinsAndSavedPins() async throws {
  let suite = "nessa-test-\(UUID())"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  defaults.set(
    ["codex", "claude", "codex", "research", "writer"],
    forKey: "nessa.pinnedChats.wss://one/session:phone")
  let store = MessagesViewModel(
    service: MessagingService(repository: FixtureGateway()), credentials: FixtureCredentials(),
    preferences: UserDefaultsChatPreferences(defaults))
  await store.connect(address: "wss://one/session", credential: "fixture", instance: "phone")
  #expect(store.pinnedChats == ["codex", "claude", "research"])
  #expect(
    defaults.stringArray(forKey: "nessa.pinnedChats.wss://one/session:phone") == store.pinnedChats)
  #expect(!store.canTogglePin("writer"))
  store.togglePin("writer")
  #expect(store.pinnedChats.count == 3)
  #expect(store.canTogglePin("claude"))
  store.togglePin("claude")
  store.togglePin("writer")
  #expect(store.pinnedChats == ["codex", "research", "writer"])
}
