import Foundation
import Testing

@testable import NessaFeatures

private let emptyChat = "00000000-0000-4000-8000-0000000000aa"

private actor ProductListGateway: MessagingRepository, ConversationFollowing, AgentDirectory {
  var lists = 0
  var reads = 0
  var followedAfter: [ConversationCursor?] = []
  func connect(address: String, credential: String, instance: String) async throws {}
  func list() async throws -> NessaConversationList {
    lists += 1
    return NessaConversationList(
      conversations: [
        NessaConversation(
          conversationId: emptyChat, title: nil, preview: nil, updatedAtMs: 2, running: false)
      ], complete: true)
  }
  func read(_ id: String) async throws -> NessaConversationView { try view(id) }
  func create(agent: String?, model: String?) async throws -> String { emptyChat }
  func send(_ text: String, attachments: [DraftAttachment], conversationID: String) async throws
    -> String
  { "unused" }
  func answer(
    _ permission: NessaPermission, option: NessaPermission.Option, conversationID: String
  ) async throws {}
  func delete(_ conversationID: String) async throws {}
  func listArchived() -> NessaConversationList { .init(conversations: [], complete: true) }
  func setArchived(_ archived: Bool, conversationID: String) {}
  func disconnect() async {}
  func agents() async throws -> [AgentProfile] { [] }
  private var conversationFollows = 0
  func follow(_ id: String?, after: ConversationCursor?) async throws
    -> AsyncThrowingStream<ConversationUpdate, Error>
  {
    followedAfter.append(after)
    let (stream, continuation) = AsyncThrowingStream<ConversationUpdate, Error>.makeStream()
    if let id {
      conversationFollows += 1
      continuation.yield(
        .view(try ConversationCursor(incarnation: "live", position: "4"), try view(id)))
      if conversationFollows == 1 {
        continuation.finish(throwing: ConversationFeedEnded(reason: .lagging, code: nil))
      } else {
        continuation.finish()
      }
    } else {
      continuation.yield(.list(try await list()))
      continuation.finish()
    }
    return stream
  }
  private func view(_ id: String) throws -> NessaConversationView {
    reads += 1
    return NessaConversationView(
      conversationId: id,
      messages: [
        NessaTurn(
          executionId: "22222222-2222-4222-8222-222222222222", userText: "Hello", status: "running",
          error: nil,
          parts: [NessaPart(offset: 0, kind: "text", text: "On my way.", messageId: nil)])
      ], permissions: [], truncated: false, interactionViewError: nil, runtime: nil)
  }
}

private final class CatalogueSpy: PhoneSyncRunning, @unchecked Sendable {
  var displays = 0
  var catalogues = 0
  private let snapshot: PhoneProfileSnapshot
  init(_ snapshot: PhoneProfileSnapshot) { self.snapshot = snapshot }
  func startup() async throws -> PhoneSyncStartup? {
    .init(
      snapshot: snapshot,
      connection: .init(
        address: snapshot.profile.productAddress, credential: "fixture",
        instance: snapshot.profile.instance))
  }
  func savedProfiles() async throws -> PhoneProfiles? { snapshot.registry }
  func display(on lease: GatewayConnectionLease?, conversations: [String], revision: UUID)
    async throws -> PhoneRetainedDisplay
  {
    displays += 1
    throw PhoneSyncRuntimeRefusal.unavailable
  }
  func suspend() async throws {}
  func restore() async throws -> PhoneProfileSnapshot? { snapshot }
  func prepare(_ desired: PhoneProfile, credential: String, on lease: GatewayConnectionLease)
    async throws -> PhoneProfileSnapshot
  { throw PhoneSyncRuntimeRefusal.unavailable }
  func startPairing(on lease: GatewayConnectionLease) async throws -> PhoneProfileSnapshot {
    throw PhoneSyncRuntimeRefusal.unavailable
  }
  func resolveInvitation(_ invitation: Data, on lease: GatewayConnectionLease) async throws
    -> PhoneProfileSnapshot
  { throw PhoneSyncRuntimeRefusal.unavailable }
  func discardUnenrolled() async throws -> PhoneProfileSnapshot {
    throw PhoneSyncRuntimeRefusal.unavailable
  }
  func observePairing(on lease: GatewayConnectionLease) async throws -> PhoneProfileSnapshot {
    throw PhoneSyncRuntimeRefusal.unavailable
  }
  func approve(_ confirmation: PhonePairingConfirmation, on lease: GatewayConnectionLease)
    async throws -> PhoneProfileSnapshot
  { throw PhoneSyncRuntimeRefusal.unavailable }
  func cancelPairing(on lease: GatewayConnectionLease) async throws -> PhoneProfileSnapshot {
    throw PhoneSyncRuntimeRefusal.unavailable
  }
  func refresh(on lease: GatewayConnectionLease?) async throws -> PhoneProfileSnapshot {
    throw PhoneSyncRuntimeRefusal.unavailable
  }
  func close() async throws {}
  func cataloguePage(after: RetainedEntryKey?, maximum: UInt32) async throws
    -> PhoneScopedRetention<RetainedCataloguePage?>
  {
    catalogues += 1
    throw PhoneSyncRuntimeRefusal.unavailable
  }
  func transcript(conversation: String, revision: UUID) async throws -> PhoneScopedRetention<
    RetainedTranscript
  > {
    catalogues += 1
    throw PhoneSyncRuntimeRefusal.unavailable
  }
}

@Test @MainActor func productChatShowsEmptyChatsAndRepliesWithoutCatalogue() async throws {
  let profile = exampleProfile(phase: .prepared).recording(
    pairingStatus: nil, nativeReceiver: "native-receiver", nativeStatus: nil, recoveredPurge: nil,
    retired: false)
  let snapshot = try PhoneProfileSnapshot(
    registry: exampleProfiles(profile), local: nil, nativeStatus: nil, source: nil)
  let sync = CatalogueSpy(snapshot)
  let gateway = ProductListGateway()
  let store = MemoryOutboxStore()
  let transport = ScriptedGateway(store: store, sendAnswers: [.receipt(.queued)])
  let chat = PhoneProductChat(
    outbox: PhoneOutbox(store: store, gateway: transport), transport: transport,
    stops: MemoryStopStore())
  let model = MessagesViewModel(
    service: MessagingService(repository: gateway), credentials: InMemoryCredentialStore(),
    preferences: InMemoryChatPreferences(), phoneSync: sync, phoneChat: chat)
  await model.connect(
    address: profile.productAddress, credential: "fixture", instance: profile.instance)
  #expect(model.conversations.map(\.id) == [emptyChat])
  #expect(model.conversations.first?.title == nil)
  #expect(model.conversations.first?.preview == nil)
  #expect(sync.displays == 0 && sync.catalogues == 0)
  await model.watchInbox()
  #expect(model.conversations.map(\.id) == [emptyChat])
  await model.watchConversation(emptyChat)
  #expect(model.views[emptyChat]?.messages.first?.parts.first?.text == "On my way.")
  let cursors = await gateway.followedAfter
  #expect(cursors.count >= 3)
  #expect(cursors[2]?.position == "4")
  let identity = MessageCommandIdentity(
    requestID: "11111111-1111-4111-8111-111111111111",
    executionID: "22222222-2222-4222-8222-222222222222")
  #expect(await model.send("Hello", to: emptyChat, identity: identity))
  #expect(await model.send("Hello", to: emptyChat, identity: identity))
  #expect(transport.sends == 1)
  #expect(sync.displays == 0 && sync.catalogues == 0)
}

@Test func eachConnectionKeepsItsOwnOutbox() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let gateway = ScriptedGateway(
    store: MemoryOutboxStore(), sendAnswers: [.receipt(.queued)])
  let chat = PhoneProductChat(root: root, transport: gateway)
  let first = PhoneCacheScope(
    address: "wss://a.example/session", credential: "one", instance: "phone")
  let second = PhoneCacheScope(
    address: "wss://b.example/session", credential: "two", instance: "phone")
  let identity = MessageCommandIdentity(
    requestID: "11111111-1111-4111-8111-111111111111",
    executionID: "22222222-2222-4222-8222-222222222222")
  await chat.activate(first)
  _ = try await chat.deliver(
    text: "Hello", attachments: [], conversationID: emptyChat, identity: identity)
  await chat.activate(second)
  #expect(try await chat.list().isEmpty)
  await chat.activate(first)
  #expect(try await chat.list().map(\.text) == ["Hello"])
}

@Test func aFailedSendStaysListedAfterRecovery() async throws {
  let store = MemoryOutboxStore()
  let gateway = ScriptedGateway(store: store, sendAnswers: [.refused("forbidden")])
  let chat = PhoneProductChat(
    outbox: PhoneOutbox(store: store, gateway: gateway), transport: gateway,
    stops: MemoryStopStore())
  _ = try await chat.deliver(
    text: "Hello", attachments: [], conversationID: emptyChat,
    identity: MessageCommandIdentity(
      requestID: "11111111-1111-4111-8111-111111111111",
      executionID: "22222222-2222-4222-8222-222222222222"))
  #expect(try await chat.recover().isEmpty)
  #expect(try await chat.list().map(\.outcome) == [.failed("forbidden")])
}

@Test @MainActor func aNewCredentialClearsRevocationAndThePreviousOutbox() async throws {
  let profile = exampleProfile(phase: .prepared).recording(
    pairingStatus: nil, nativeReceiver: "native-receiver", nativeStatus: nil, recoveredPurge: nil,
    retired: false)
  let snapshot = try PhoneProfileSnapshot(
    registry: exampleProfiles(profile), local: nil, nativeStatus: nil, source: nil)
  let gateway = ProductListGateway()
  let transport = ScriptedGateway(
    store: MemoryOutboxStore(), sendAnswers: [.refused("forbidden")])
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let model = MessagesViewModel(
    service: MessagingService(repository: gateway), credentials: InMemoryCredentialStore(),
    preferences: InMemoryChatPreferences(), phoneSync: CatalogueSpy(snapshot),
    phoneChat: PhoneProductChat(root: root, transport: transport))
  await model.connect(
    address: profile.productAddress, credential: "fixture", instance: profile.instance)
  let identity = MessageCommandIdentity(
    requestID: "11111111-1111-4111-8111-111111111111",
    executionID: "22222222-2222-4222-8222-222222222222")
  #expect(await model.send("Hello", to: emptyChat, identity: identity) == false)
  #expect(model.accessRevoked)
  #expect(model.phoneDeliveries(in: emptyChat).map(\.outcome) == [.failed("forbidden")])
  await model.connect(
    address: "ws://127.0.0.1:18744/session", credential: "replacement", instance: "other-phone")
  #expect(!model.accessRevoked)
  #expect(model.phoneDeliveries(in: emptyChat).isEmpty)
  #expect(model.canSubmit(in: emptyChat))
}

@Test @MainActor func anOldRevocationDoesNotLockTheSameAccountAgain() async throws {
  let profile = exampleProfile(phase: .prepared).recording(
    pairingStatus: nil, nativeReceiver: "native-receiver", nativeStatus: nil, recoveredPurge: nil,
    retired: false)
  let snapshot = try PhoneProfileSnapshot(
    registry: exampleProfiles(profile), local: nil, nativeStatus: nil, source: nil)
  let transport = ScriptedGateway(
    store: MemoryOutboxStore(), sendAnswers: [.refused("forbidden")])
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  let model = MessagesViewModel(
    service: MessagingService(repository: ProductListGateway()),
    credentials: InMemoryCredentialStore(), preferences: InMemoryChatPreferences(),
    phoneSync: CatalogueSpy(snapshot), phoneChat: PhoneProductChat(root: root, transport: transport))
  await model.connect(
    address: profile.productAddress, credential: "fixture", instance: profile.instance)
  #expect(
    await model.send(
      "Hello", to: emptyChat,
      identity: MessageCommandIdentity(
        requestID: "11111111-1111-4111-8111-111111111111",
        executionID: "22222222-2222-4222-8222-222222222222")) == false)
  #expect(model.accessRevoked)
  await model.connect(
    address: profile.productAddress, credential: "fixture", instance: profile.instance)
  #expect(!model.accessRevoked)
  #expect(model.phoneDeliveries(in: emptyChat).map(\.outcome) == [.failed("forbidden")])
  #expect(model.canSubmit(in: emptyChat))
}

private actor MemoryStopStore: PhoneStopStoring {
  private var records: [PhoneStopRecord] = []
  func load() async throws -> [PhoneStopRecord] { records }
  func save(_ records: [PhoneStopRecord]) async throws { self.records = records }
}
