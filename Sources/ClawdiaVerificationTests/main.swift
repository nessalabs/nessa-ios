import Foundation
import SharedKernel
import ClawdiaDesignSystem
import ClawdiaFeatures

struct VerificationFailure: Error, CustomStringConvertible {
    let description: String
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw VerificationFailure(description: message)
    }
}

func hexString(_ data: Data) -> String {
    data.map { String(format: "%02x", $0) }.joined()
}

func dataFromHex(_ hex: String) throws -> Data {
    guard hex.count.isMultiple(of: 2) else {
        throw VerificationFailure(description: "hex fixture should have an even length")
    }
    var data = Data()
    var index = hex.startIndex
    while index < hex.endIndex {
        let nextIndex = hex.index(index, offsetBy: 2)
        guard let byte = UInt8(hex[index..<nextIndex], radix: 16) else {
            throw VerificationFailure(description: "hex fixture should only contain hex characters")
        }
        data.append(byte)
        index = nextIndex
    }
    return data
}

func encodeAgentEnvelope(_ envelope: AgentMessageEnvelope) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(envelope)
    guard let json = String(data: data, encoding: .utf8) else {
        throw VerificationFailure(description: "agent envelope should encode as UTF-8 JSON")
    }
    return json
}

func storedMessage(
    id: UUID = UUID(),
    conversationID: String,
    area: LifeArea,
    sender: AgentMessageSender = .phone,
    text: String = "Test message",
    createdAt: Date
) -> StoredChatMessage {
    StoredChatMessage(
        id: id,
        conversationID: conversationID,
        area: area.rawValue,
        sender: sender,
        text: text,
        createdAt: createdAt,
        expiresAt: createdAt.addingTimeInterval(60 * 60),
        deliveryState: sender == .phone ? .sent : .received
    )
}

func testSharedKernel() throws {
    let value = NonEmptyString("  Clawdia  ")
    try expect(value.value == "Clawdia", "NonEmptyString should trim whitespace")

    let id = EntityID<String>()
    try expect(EntityID<String>(rawValue: id.rawValue) == id, "EntityID should round-trip raw values")
}

func testDesignSystemTokens() throws {
    try expect(ClawdiaColor.palette(.light).folders.count == 6, "light theme should expose six folder colors")
    try expect(ClawdiaColor.palette(.dark).folders.count == 6, "dark theme should expose six folder colors")
    try expect(ClawdiaSpacing.xs < ClawdiaSpacing.sm, "spacing scale xs < sm")
    try expect(ClawdiaSpacing.sm < ClawdiaSpacing.md, "spacing scale sm < md")
    try expect(ClawdiaSpacing.md < ClawdiaSpacing.lg, "spacing scale md < lg")
    try expect(ClawdiaSpacing.lg < ClawdiaSpacing.xl, "spacing scale lg < xl")
}

func testFeatureCatalog() throws {
    let titles = Set(DevScreen.allCases.map(\.title))
    let expected: Set<String> = [
        "Onboarding",
        "Home",
        "Chat",
        "Voice",
        "Approvals",
        "Search",
        "Calendar",
        "Folders",
        "Settings",
        "Connected Apps",
        "Memory",
        "Context Notes",
        "Context Board",
        "Design System"
    ]
    try expect(titles.isSuperset(of: expected), "dev screen catalog should cover all expected mock screens")

    let state = MockAppState.preview
    try expect(state.folders.count == 6, "preview state should contain six folders")
    try expect(state.chats.count >= 4, "preview state should contain chat rows")
    try expect(state.approvals.count >= ApprovalKind.allCases.count, "preview state should contain approval and diff examples")
    try expect(Set(state.approvals.map(\.kind)) == Set(ApprovalKind.allCases), "preview approvals should cover every approval kind")
    try expect(state.connection == .connected(.localhost(port: 8787)), "preview state should default to localhost connection")
}

func testProductionStateUsesRealAgentThreads() throws {
    let state = MockAppState.production

    try expect(state.connection == .disconnected, "production state should not default to localhost dev wiring")
    try expect(state.approvals.isEmpty, "production state should not show approval examples")
    try expect(state.chats.count == LifeArea.allCases.count, "production should expose one Clawdia thread per built-in area")
    try expect(Set(state.chats.map(\.title)) == ["Clawdia"], "production should remove example chat titles")
    try expect(Set(state.chats.map(\.id)) == Set(LifeArea.allCases.map(\.defaultChatID)), "production chat threads should use stable ids for persisted history")
    try expect(!state.chats.contains { $0.title == "Mia's birthday" || $0.title == "Q4 planning" }, "production should not include preview/demo chat rows")
}

func testIPhoneDataConnectionsDefaultToProductionOptions() throws {
    let state = MockAppState.production

    try expect(
        Set(state.iPhoneDataConnections.map(\.kind)) == Set(IPhoneDataConnectionKind.allCases),
        "production state should expose iCloud, Health, and Location data connection settings"
    )
    try expect(
        state.iPhoneDataConnections.allSatisfy { $0.status == .notDetermined },
        "production iPhone data connections should start permission-gated"
    )
}

func testStoreRequestsIPhoneDataConnectionForDesktopAnalysis() throws {
    let provider = RecordingIPhoneDataConnectionProvider(requestedConnection: IPhoneDataConnection(
        kind: .health,
        status: .connected,
        includeInDesktopAnalysis: true
    ))
    let store = DevModeStore(
        state: .production,
        iPhoneDataConnectionProvider: provider
    )

    store.requestIPhoneDataConnection(.health)
    waitUntil {
        store.state.iPhoneDataConnections.first(where: { $0.kind == .health })?.status == .connected
    }

    let health = store.state.iPhoneDataConnections.first(where: { $0.kind == .health })
    try expect(provider.requestedKinds == [.health], "store should request the selected iPhone data connection through the application port")
    try expect(health?.status == .connected, "authorized iPhone data connections should update app state")
    try expect(health?.includeInDesktopAnalysis == true, "authorized iPhone data connections should be marked for desktop analysis")
}

func testSystemProviderTreatsMissingICloudIdentityAsUnavailable() async throws {
    let provider = SystemIPhoneDataConnectionProvider(iCloudIdentityToken: { nil })

    let connections = await provider.loadConnections()
    let iCloud = connections.first(where: { $0.kind == .iCloud })

    try expect(iCloud?.status == .unavailable, "system provider should not probe CloudKit when iCloud identity is unavailable")
    try expect(iCloud?.includeInDesktopAnalysis == false, "unavailable iCloud connection should not be included in desktop analysis")
}

func testStoreDeletesChatAndPersistedConversation() throws {
    let now = Date(timeIntervalSince1970: 2_000)
    let homeChat = MockAppState.production.chats.first { $0.area == .home }!
    let workChat = MockAppState.production.chats.first { $0.area == .work }!
    let homeMessage = storedMessage(
        conversationID: homeChat.id.uuidString,
        area: .home,
        text: "Delete this chat",
        createdAt: now
    )
    let workMessage = storedMessage(
        conversationID: workChat.id.uuidString,
        area: .work,
        text: "Keep this chat",
        createdAt: now
    )
    let repository = InMemoryChatMessageRepository(messages: [homeMessage, workMessage])
    let store = DevModeStore(
        state: .production,
        chatMessageRepository: repository,
        now: { now }
    )

    store.deleteChat(homeChat)

    let active = try repository.loadActiveMessages(now: now)
    try expect(!store.state.chats.contains(where: { $0.id == homeChat.id }), "deleted chats should disappear from app state")
    try expect(!store.state.chatMessages.contains(where: { $0.conversationID == homeChat.id.uuidString }), "deleted chats should clear local message state")
    try expect(!active.contains(where: { $0.conversationID == homeChat.id.uuidString }), "deleted chats should delete persisted conversation messages")
    try expect(active.contains(where: { $0.conversationID == workChat.id.uuidString }), "deleting one chat should not remove other persisted conversations")
}

func testStoreDeletesLifeAreaAndPersistedAreaMessages() throws {
    let now = Date(timeIntervalSince1970: 3_000)
    let homeChat = MockAppState.production.chats.first { $0.area == .home }!
    let workChat = MockAppState.production.chats.first { $0.area == .work }!
    let repository = InMemoryChatMessageRepository(messages: [
        storedMessage(conversationID: homeChat.id.uuidString, area: .home, text: "Home", createdAt: now),
        storedMessage(conversationID: workChat.id.uuidString, area: .work, text: "Work", createdAt: now)
    ])
    let onboardingStore = InMemoryOnboardingConfigurationStore(
        configuration: OnboardingConfiguration(didComplete: true, selectedAreas: Set(LifeArea.allCases))
    )
    let store = DevModeStore(
        state: .production,
        onboardingStore: onboardingStore,
        chatMessageRepository: repository,
        now: { now }
    )

    store.deleteArea(.life(.home))

    let active = try repository.loadActiveMessages(now: now)
    try expect(!store.state.folders.contains(where: { $0.id == .home }), "deleted areas should disappear from the home area list")
    try expect(!store.state.chats.contains(where: { $0.area == .home }), "deleted areas should remove chats in that area")
    try expect(!store.onboardingConfiguration.selectedAreas.contains(.home), "deleted built-in areas should update persisted onboarding selection")
    try expect(!active.contains(where: { $0.area == LifeArea.home.rawValue }), "deleted areas should delete persisted messages for that area")
    try expect(active.contains(where: { $0.area == LifeArea.work.rawValue }), "deleting one area should not remove other area messages")
}

func testStoreDeletesSelectedMessagesOnly() throws {
    let now = Date(timeIntervalSince1970: 4_000)
    let chat = MockAppState.production.chats.first { $0.area == .personal }!
    let first = storedMessage(
        conversationID: chat.id.uuidString,
        area: .personal,
        text: "Remove this",
        createdAt: now
    )
    let second = storedMessage(
        conversationID: chat.id.uuidString,
        area: .personal,
        text: "Keep this",
        createdAt: now.addingTimeInterval(1)
    )
    let repository = InMemoryChatMessageRepository(messages: [first, second])
    let store = DevModeStore(
        state: .production,
        chatMessageRepository: repository,
        now: { now }
    )

    store.deleteChatMessages(ids: [first.id])

    let active = try repository.loadActiveMessages(now: now)
    try expect(!store.state.chatMessages.contains(where: { $0.id == first.id }), "selected message delete should remove only selected local state")
    try expect(store.state.chatMessages.contains(where: { $0.id == second.id }), "selected message delete should leave unselected messages in local state")
    try expect(!active.contains(where: { $0.id == first.id }), "selected message delete should remove selected persisted records")
    try expect(active.contains(where: { $0.id == second.id }), "selected message delete should leave unselected persisted records")
}

func testStoredChatMessagesRespectOneHourTTL() throws {
    let now = Date(timeIntervalSince1970: 1_000)
    let fresh = StoredChatMessage(
        conversationID: LifeArea.home.defaultChatID.uuidString,
        area: LifeArea.home.rawValue,
        sender: .phone,
        text: "Fresh",
        createdAt: now.addingTimeInterval(-59 * 60),
        expiresAt: now.addingTimeInterval(60),
        deliveryState: .sent
    )
    let expired = StoredChatMessage(
        conversationID: LifeArea.home.defaultChatID.uuidString,
        area: LifeArea.home.rawValue,
        sender: .desktopClient,
        text: "Expired",
        createdAt: now.addingTimeInterval(-61 * 60),
        expiresAt: now.addingTimeInterval(-60),
        deliveryState: .received
    )
    let repository = InMemoryChatMessageRepository(messages: [fresh, expired])

    try repository.deleteExpired(before: now)
    let active = try repository.loadActiveMessages(now: now)

    try expect(active == [fresh], "chat message repository should retain only messages inside the TTL window")
    try expect(ChatMessageRetentionPolicy.oneHour.expirationDate(for: now) == now.addingTimeInterval(60 * 60), "default chat retention should be one hour")
}

func testAppFlowAreaConfiguration() throws {
    var state = MockAppState.preview

    state.configureInitialAreas([.personal, .work])

    try expect(state.folders.map(\.id) == [.personal, .work], "onboarding area selection should keep only chosen built-in areas")
    try expect(state.chats.allSatisfy { [.personal, .work].contains($0.area) }, "onboarding area selection should keep only chats for chosen areas")
}

func testOnboardingCompletionPersistsSelectedAreas() throws {
    let onboardingStore = InMemoryOnboardingConfigurationStore()
    let store = DevModeStore(state: .preview, onboardingStore: onboardingStore)

    store.completeOnboarding(selectedAreas: [.home, .travel])

    try expect(store.onboardingConfiguration == OnboardingConfiguration(didComplete: true, selectedAreas: [.home, .travel]), "onboarding completion should store selected areas")
    try expect(store.state.folders.map(\.id) == [.home, .travel], "selected onboarding areas should filter the active folder list immediately")

    let reloadedStore = DevModeStore(state: .preview, onboardingStore: onboardingStore)
    try expect(reloadedStore.onboardingConfiguration.didComplete, "onboarding completion should survive a new store using the same persistence port")
    try expect(reloadedStore.state.folders.map(\.id) == [.home, .travel], "persisted onboarding areas should filter folders on app start")
}

func testSignOutReturnsToFreshOnboardingAndClearsPairing() throws {
    let onboardingStore = InMemoryOnboardingConfigurationStore()
    let credentialStore = RecordingNostrBridgeCredentialStore()
    let store = DevModeStore(
        state: .preview,
        onboardingStore: onboardingStore,
        nostrCredentialStore: credentialStore,
        initialDesktopPairingStatus: .paired(displayName: "Mac mini")
    )

    store.completeOnboarding(selectedAreas: [.home, .work])
    store.signOut()

    try expect(!store.onboardingConfiguration.didComplete, "sign out should return the app to initial onboarding")
    try expect(store.onboardingConfiguration.selectedAreas == LifeArea.defaultOnboardingSelection, "sign out should restore the default onboarding area selection")
    try expect(store.desktopPairingStatus == .notPaired, "sign out should clear the desktop pairing state")
    try expect(credentialStore.deleteCount == 1, "sign out should clear persisted desktop pairing credentials")
    try expect(store.state.folders.count == MockAppState.preview.folders.count, "sign out should restore the default app preview state")

    let reloadedStore = DevModeStore(state: .preview, onboardingStore: onboardingStore)
    try expect(!reloadedStore.onboardingConfiguration.didComplete, "sign out should persist the fresh onboarding state")
}

func testAppFlowCustomAreaCreationAndFiltering() throws {
    var state = MockAppState.preview

    let created = state.createCustomArea(named: "  Side Projects  ")

    try expect(created?.name == "Side Projects", "custom area creation should trim whitespace")
    try expect(state.customAreas.count == 1, "custom area creation should update application state")
    try expect(state.availableAreaCount == state.folders.count + state.customAreas.count, "available area count should include built-in and custom areas")
    try expect(state.chats(matching: .life(.work)).allSatisfy { $0.area == .work }, "life-area filtering should return only matching chats")
    try expect(state.chats(matching: .all).count == state.chats.count, "all-area filtering should return every chat")

    if let created {
        try expect(state.chats(matching: .custom(created.id)).isEmpty, "new custom areas should start without associated chats")
    }
}

func testRuntimeModeDefaultsToProductionAndUsesFlags() throws {
    let suiteName = "clawdia-runtime-mode-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer {
        defaults.removePersistentDomain(forName: suiteName)
    }

    try expect(ClawdiaRuntimeModeResolver.resolve(environment: [:], arguments: [], userDefaults: defaults) == .production, "runtime mode should default to production")
    try expect(ClawdiaRuntimeModeResolver.resolve(environment: [:], arguments: [ClawdiaRuntimeModeResolver.launchArgument], userDefaults: defaults) == .development, "runtime mode should support a launch argument development flag")
    try expect(ClawdiaRuntimeModeResolver.resolve(environment: [ClawdiaRuntimeModeResolver.environmentKey: "development"], arguments: [], userDefaults: defaults) == .development, "runtime mode should support an environment development flag")

    defaults.set(true, forKey: ClawdiaRuntimeModeResolver.userDefaultsKey)
    try expect(ClawdiaRuntimeModeResolver.resolve(environment: [:], arguments: [], userDefaults: defaults) == .development, "runtime mode should support a user defaults development flag")
}

func testPreviewChatsAreScopedToAreas() throws {
    let state = MockAppState.preview

    for folder in state.folders {
        let areaChats = state.chats(matching: .life(folder.id))
        try expect(!areaChats.isEmpty, "\(folder.id.title) should have preview chats")
        try expect(folder.chatCount == areaChats.count, "\(folder.id.title) chat count should match its preview chats")
        try expect(areaChats.allSatisfy { $0.area == folder.id }, "\(folder.id.title) preview chats should stay in that area")
    }
}

func testAreaChatNavigationKeepsAreaRouteBehindChat() throws {
    let state = MockAppState.preview
    guard let homeChat = state.chats(matching: .life(.home)).first else {
        throw VerificationFailure(description: "Home should have a preview chat for route verification")
    }

    let path: [AppNavigationRoute] = [.area(.life(.home)), .chat(homeChat)]

    try expect(path.first == .area(.life(.home)), "area route should stay behind chat route")
    try expect(path.last == .chat(homeChat), "chat route should be pushed after its area route")
}

func testCalendarCurrentDateResolver() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let may8 = calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: 2026, month: 5, day: 8))!

    try expect(CalendarCurrentDateResolver.dayID(for: may8, calendar: calendar) == "2026-may-8", "calendar should resolve May 8, 2026 as the current demo day")
    try expect(CalendarCurrentDateResolver.monthKey(for: may8, calendar: calendar) == "may", "calendar should resolve the current month key")
}

func testNostrAgentEnvelopeDraftShape() throws {
    let chat = ChatPreview(
        title: "Apartment tasks",
        preview: "Filters, laundry, and the package pickup are still open.",
        time: "Yesterday",
        area: .home
    )
    let configuration = NostrAgentBridgeConfiguration(
        phonePublicKey: String(repeating: "a", count: 64),
        desktopPublicKey: String(repeating: "b", count: 64),
        relayURLs: []
    )

    let draft = NostrAgentEventFactory(configuration: configuration)
        .makeChatMessageDraft(text: "Please check the package pickup.", chat: chat, now: Date(timeIntervalSince1970: 1_777_777_777))

    try expect(draft.kind == NostrAgentEventFactory.ephemeralAgentMessageKind, "agent message drafts should use the app ephemeral event kind")
    try expect(draft.pubkey == configuration.phonePublicKey, "agent event should publish from the phone pubkey")
    try expect(draft.tags.contains(["p", configuration.desktopPublicKey]), "agent event should target the desktop pubkey with a p tag")
    try expect(draft.tags.contains(["app", "clawdia"]), "agent event should identify the app namespace")
    try expect(draft.tags.contains(["schema", AgentMessageEnvelope.schema]), "agent event should identify the envelope schema")
    try expect(draft.content.contains("Please check the package pickup."), "agent event content should include the outgoing message payload")
    try expect(draft.content.contains("\"area\":\"home\""), "agent event content should keep area context")
}

func testStoreQueuesNostrEventOnChatSend() throws {
    let state = MockAppState.preview
    guard let chat = state.chats(matching: .life(.home)).first else {
        throw VerificationFailure(description: "Home should have a preview chat for Nostr send verification")
    }
    let store = DevModeStore(state: state)

    let queued = store.sendChatMessage("Can you check the package?", in: chat)

    try expect(queued?.draft.kind == NostrAgentEventFactory.ephemeralAgentMessageKind, "chat sends should queue a Nostr agent event")
    try expect(queued?.delivery == .requiresEncryptedGiftWrap, "queued Nostr events should require encrypted gift wrapping before relay publish")
    try expect(store.state.outgoingNostrEvents.count == 1, "store should retain queued outgoing Nostr events in phone memory")
    try expect(store.state.outgoingNostrEvents.first?.draft.content.contains("Can you check the package?") == true, "queued Nostr event should include the sent chat text")
}

final class RecordingNostrMessageSender: NostrAgentMessageSending {
    private(set) var sentEvents: [NostrOutboxEvent] = []
    private let preparedEvent: NostrPreparedRelayEvent

    init(preparedEvent: NostrPreparedRelayEvent) {
        self.preparedEvent = preparedEvent
    }

    func send(_ event: NostrOutboxEvent) throws -> NostrPreparedRelayEvent {
        sentEvents.append(event)
        return preparedEvent
    }
}

final class RecordingIPhoneDataConnectionProvider: IPhoneDataConnectionProviding, @unchecked Sendable {
    private let lock = NSLock()
    private let requestedConnection: IPhoneDataConnection
    private var requested: [IPhoneDataConnectionKind] = []

    init(requestedConnection: IPhoneDataConnection) {
        self.requestedConnection = requestedConnection
    }

    var requestedKinds: [IPhoneDataConnectionKind] {
        lock.withLock { requested }
    }

    func loadConnections() async -> [IPhoneDataConnection] {
        IPhoneDataConnection.defaults()
    }

    func requestConnection(_ kind: IPhoneDataConnectionKind) async -> IPhoneDataConnection {
        lock.withLock {
            requested.append(kind)
        }
        return requestedConnection
    }
}

func waitUntil(timeout: TimeInterval = 2, condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() {
            return
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    }
}

final class SequenceNostrEntropySource: NostrEntropySource {
    private var values: [Data]

    init(_ values: [Data]) {
        self.values = values
    }

    func bytes(count: Int) throws -> Data {
        guard !values.isEmpty else {
            throw VerificationFailure(description: "deterministic Nostr entropy source ran out of values")
        }
        let value = values.removeFirst()
        guard value.count == count else {
            throw VerificationFailure(description: "deterministic Nostr entropy value should have \(count) bytes")
        }
        return value
    }
}

final class RecordingNostrRelayPublisher: NostrRelayPublishing, @unchecked Sendable {
    private let lock = NSLock()
    private var publishedEvents: [NostrPreparedRelayEvent] = []
    private let receipts: [NostrRelayPublishReceipt]
    private let onPublish: (@Sendable () -> Void)?

    init(receipts: [NostrRelayPublishReceipt], onPublish: (@Sendable () -> Void)? = nil) {
        self.receipts = receipts
        self.onPublish = onPublish
    }

    func publish(_ event: NostrPreparedRelayEvent) async -> [NostrRelayPublishReceipt] {
        lock.withLock {
            publishedEvents.append(event)
        }
        onPublish?()
        return receipts
    }

    func publishedEventIDs() -> [String] {
        lock.withLock {
            publishedEvents.map(\.id)
        }
    }
}

final class NostrReceiptBox: @unchecked Sendable {
    private let lock = NSLock()
    private var receipts: [NostrRelayPublishReceipt] = []

    func set(_ receipts: [NostrRelayPublishReceipt]) {
        lock.withLock {
            self.receipts = receipts
        }
    }

    func get() -> [NostrRelayPublishReceipt] {
        lock.withLock {
            receipts
        }
    }
}

final class RecordingNostrBridgeCredentialStore: NostrAgentBridgeCredentialStoring {
    private(set) var savedCredentials: NostrAgentBridgeCredentials?
    private(set) var deleteCount = 0

    func loadCredentials() throws -> NostrAgentBridgeCredentials? {
        savedCredentials
    }

    func saveCredentials(_ credentials: NostrAgentBridgeCredentials) throws {
        savedCredentials = credentials
    }

    func deleteCredentials() throws {
        deleteCount += 1
        savedCredentials = nil
    }
}

func testStorePreparesRelayEventWhenSenderIsConfigured() throws {
    let state = MockAppState.preview
    guard let chat = state.chats(matching: .life(.home)).first else {
        throw VerificationFailure(description: "Home should have a preview chat for Nostr send verification")
    }
    let preparedEvent = NostrPreparedRelayEvent(
        id: String(repeating: "1", count: 64),
        pubkey: String(repeating: "2", count: 64),
        createdAt: 1_777_777_777,
        kind: 1059,
        tags: [["p", String(repeating: "3", count: 64)]],
        content: "encrypted-payload",
        signature: String(repeating: "4", count: 128),
        relayURLs: []
    )
    let sender = RecordingNostrMessageSender(preparedEvent: preparedEvent)
    let repository = InMemoryChatMessageRepository()
    let sentAt = Date(timeIntervalSince1970: 1_777_777_700)
    let store = DevModeStore(
        state: state,
        nostrMessageSender: sender,
        chatMessageRepository: repository,
        now: { sentAt }
    )

    _ = store.sendChatMessage("Can you send this over Nostr?", in: chat)

    try expect(sender.sentEvents.count == 1, "configured Nostr senders should receive chat outbox events")
    try expect(store.state.preparedNostrRelayEvents == [preparedEvent], "prepared relay events should stay in phone memory")
    let persisted = try repository.loadActiveMessages(now: sentAt)
    try expect(persisted.count == 1, "sent chat messages should be persisted on the phone")
    try expect(persisted.first?.text == "Can you send this over Nostr?", "persisted outgoing chat message should keep the sent text")
    try expect(persisted.first?.expiresAt == sentAt.addingTimeInterval(60 * 60), "persisted outgoing chat message should carry a one-hour TTL")
    try expect(persisted.first?.deliveryState == .sent, "prepared Nostr messages should be marked sent in local history")
    try expect(store.state.isAgentTyping(conversationID: chat.id.uuidString), "phone UI should show desktop typing after a successful send")
}

func testPreparedRelayEventEncodesNIP01ClientFrame() throws {
    let recipientPublicKeyHex = String(repeating: "3", count: 64)
    let relayEvent = NostrPreparedRelayEvent(
        id: String(repeating: "1", count: 64),
        pubkey: String(repeating: "2", count: 64),
        createdAt: 1_777_777_777,
        kind: 1059,
        tags: [["p", recipientPublicKeyHex]],
        content: "encrypted-payload",
        signature: String(repeating: "4", count: 128),
        relayURLs: [URL(string: "wss://relay.example.com")!]
    )

    let relayMessage = try relayEvent.relayClientMessageJSON()

    try expect(relayMessage.hasPrefix("[\"EVENT\","), "relay client messages should start with the NIP-01 EVENT frame")
    try expect(relayMessage.contains("\"kind\":1059"), "relay client messages should carry the gift wrap kind")
    try expect(relayMessage.contains("[\"p\","), "relay client messages should include a p tag")
    try expect(relayMessage.contains(recipientPublicKeyHex), "relay client messages should route to the recipient pubkey")
    try expect(relayMessage.contains("wss://relay.example.com") == false, "relay URLs should stay local and not be encoded into event JSON")
}

func testRelaySubscriptionEncodesNIP01Request() throws {
    let recipientPublicKeyHex = String(repeating: "3", count: 64)
    let subscription = NostrRelaySubscription(
        id: "phone-inbox",
        relayURLs: [URL(string: "wss://relay.example.com")!],
        recipientPublicKey: recipientPublicKeyHex
    )

    let relayMessage = try subscription.relayClientMessageJSON()
    guard let data = relayMessage.data(using: .utf8),
          let values = try JSONSerialization.jsonObject(with: data) as? [Any],
          values.count == 3,
          values[0] as? String == "REQ",
          values[1] as? String == "phone-inbox",
          let filter = values[2] as? [String: Any],
          let pTags = filter["#p"] as? [String],
          let kinds = filter["kinds"] as? [Int] else {
        throw VerificationFailure(description: "relay subscription should encode as a NIP-01 REQ frame")
    }

    try expect(pTags == [recipientPublicKeyHex], "relay subscription should filter gift wraps by recipient pubkey")
    try expect(kinds == [1059], "relay subscription should listen for NIP-59 gift wraps")
    try expect(relayMessage.contains("wss://relay.example.com") == false, "relay URLs should stay local and not be encoded into subscription JSON")
}

func testNostrRelayEventResponseParsing() throws {
    let relayURL = URL(string: "wss://relay.example.com")!
    let relayEvent = NostrPreparedRelayEvent(
        id: String(repeating: "1", count: 64),
        pubkey: String(repeating: "2", count: 64),
        createdAt: 1_777_777_777,
        kind: 1059,
        tags: [["p", String(repeating: "3", count: 64)]],
        content: "encrypted-payload",
        signature: String(repeating: "4", count: 128),
        relayURLs: []
    )
    let eventData = try JSONEncoder().encode(relayEvent)
    guard let eventJSON = String(data: eventData, encoding: .utf8) else {
        throw VerificationFailure(description: "relay event should encode as UTF-8 JSON")
    }

    let parsed = NostrRelayResponseParser.preparedEvent(
        fromRelayMessage: "[\"EVENT\",\"phone-inbox\",\(eventJSON)]",
        relayURL: relayURL
    )

    try expect(parsed == NostrPreparedRelayEvent(
        id: relayEvent.id,
        pubkey: relayEvent.pubkey,
        createdAt: relayEvent.createdAt,
        kind: relayEvent.kind,
        tags: relayEvent.tags,
        content: relayEvent.content,
        signature: relayEvent.signature,
        relayURLs: [relayURL]
    ), "relay EVENT parser should recover a prepared gift wrap with its source relay")
}

func testNIP44OfficialVector() throws {
    let sec1 = String(repeating: "0", count: 63) + "1"
    let sec2 = String(repeating: "0", count: 63) + "2"
    let nonce = try dataFromHex(String(repeating: "0", count: 63) + "1")
    let keypair1 = try NostrAgentKeypair(privateKeyHex: sec1)
    let keypair2 = try NostrAgentKeypair(privateKeyHex: sec2)
    let cipher = NostrNIP44Cipher()

    let conversationKey = try cipher.conversationKey(privateKeyHex: sec1, publicKeyHex: keypair2.publicKeyHex)
    try expect(hexString(conversationKey) == "c41c775356fd92eadc63ff5a0dc1da211b268cbea22316767095b2871ea1412d", "NIP-44 conversation key should match the official vector")

    let payload = try cipher.encrypt(plaintext: "a", conversationKey: conversationKey, nonce: nonce)
    try expect(payload == "AgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAABee0G5VSK0/9YypIObAtDKfYEAjD35uVkHyB0F4DwrcNaCXlCWZKaArsGrY6M9wnuTMxWfp1RTN9Xga8no+kF5Vsb", "NIP-44 payload should match the official vector")

    let decrypted = try cipher.decrypt(payload: payload, privateKeyHex: sec2, publicKeyHex: keypair1.publicKeyHex)
    try expect(decrypted == "a", "NIP-44 payload should decrypt from the recipient side")
}

func testEncryptedNostrSenderPreparesGiftWrap() throws {
    let phonePrivateKey = String(repeating: "0", count: 63) + "1"
    let desktopPrivateKey = String(repeating: "0", count: 63) + "2"
    let wrapperPrivateKey = String(repeating: "0", count: 63) + "3"
    let phoneKeypair = try NostrAgentKeypair(privateKeyHex: phonePrivateKey)
    let desktopKeypair = try NostrAgentKeypair(privateKeyHex: desktopPrivateKey)
    let relayURL = URL(string: "wss://relay.example.com")!
    let chat = ChatPreview(
        title: "Apartment tasks",
        preview: "Package pickup is open.",
        time: "Now",
        area: .home
    )
    let configuration = NostrAgentBridgeConfiguration(
        phonePublicKey: phoneKeypair.publicKeyHex,
        desktopPublicKey: desktopKeypair.publicKeyHex,
        relayURLs: [relayURL]
    )
    let outboxEvent = NostrAgentEventFactory(configuration: configuration)
        .queueChatMessage(text: "Can you check the package?", chat: chat, now: Date(timeIntervalSince1970: 1_777_777_777))
    let entropy = SequenceNostrEntropySource([
        Data(repeating: 1, count: 32),
        try dataFromHex(wrapperPrivateKey),
        Data(repeating: 4, count: 32)
    ])
    let sender = try NostrEncryptedAgentMessageSender(phonePrivateKeyHex: phonePrivateKey, entropy: entropy)

    let prepared = try sender.send(outboxEvent)
    let wrapperKeypair = try NostrAgentKeypair(privateKeyHex: wrapperPrivateKey)

    try expect(prepared.kind == 1059, "encrypted Nostr sender should prepare a NIP-59 gift wrap event")
    try expect(prepared.tags == [["p", desktopKeypair.publicKeyHex]], "gift wrap should route to the desktop recipient")
    try expect(prepared.relayURLs == [relayURL], "relay URLs should remain local delivery metadata")
    try expect(prepared.pubkey == wrapperKeypair.publicKeyHex, "gift wrap should be signed by the ephemeral wrapper key")
    try expect(prepared.signature.count == 128, "gift wrap should include a Schnorr signature")
    try expect(prepared.content.contains("Can you check the package?") == false, "gift wrap content should not expose plaintext")
    try expect(prepared.content.contains(AgentMessageEnvelope.schema) == false, "gift wrap content should not expose the app message schema")
}

func testEncryptedNostrReceiverUnwrapsDesktopEnvelope() throws {
    let phonePrivateKey = String(repeating: "0", count: 63) + "1"
    let desktopPrivateKey = String(repeating: "0", count: 63) + "2"
    let wrapperPrivateKey = String(repeating: "0", count: 63) + "3"
    let phoneKeypair = try NostrAgentKeypair(privateKeyHex: phonePrivateKey)
    let desktopKeypair = try NostrAgentKeypair(privateKeyHex: desktopPrivateKey)
    let envelope = AgentMessageEnvelope(
        conversationID: "home:apartment",
        area: "home",
        sender: .desktopClient,
        kind: .diffReference,
        text: "Review this desktop diff.",
        attachments: [
            AgentMessageAttachment(
                kind: .diffReference,
                name: "settings.diff",
                contentType: "text/x-diff",
                localReference: "clawdia://desktop/context/settings-diff"
            )
        ],
        createdAt: 1_777_777_777
    )
    let draft = NostrEventDraft(
        pubkey: desktopKeypair.publicKeyHex,
        createdAt: 1_777_777_777,
        kind: NostrAgentEventFactory.ephemeralAgentMessageKind,
        tags: [
            ["p", phoneKeypair.publicKeyHex],
            ["app", "clawdia"],
            ["schema", AgentMessageEnvelope.schema],
            ["conversation", "home:apartment"],
            ["area", "home"]
        ],
        content: try encodeAgentEnvelope(envelope)
    )
    let outboxEvent = NostrOutboxEvent(
        draft: draft,
        relayURLs: [URL(string: "wss://relay.example.com")!],
        delivery: .requiresEncryptedGiftWrap
    )
    let sender = try NostrEncryptedAgentMessageSender(
        phonePrivateKeyHex: desktopPrivateKey,
        entropy: SequenceNostrEntropySource([
            Data(repeating: 7, count: 32),
            try dataFromHex(wrapperPrivateKey),
            Data(repeating: 8, count: 32)
        ])
    )
    let receiver = try NostrEncryptedAgentMessageReceiver(
        phonePrivateKeyHex: phonePrivateKey,
        expectedSenderPublicKeyHex: desktopKeypair.publicKeyHex
    )

    let prepared = try sender.send(outboxEvent)
    let received = try receiver.receive(prepared)

    try expect(received == envelope, "phone receiver should unwrap the desktop envelope exactly")
    try expect(prepared.content.contains("Review this desktop diff.") == false, "received gift wrap should not expose desktop plaintext")
    try expect(prepared.content.contains("settings.diff") == false, "received gift wrap should not expose desktop attachment names")
}

func testStoreStoresIncomingNostrEnvelopeInPhoneMemory() throws {
    let phonePrivateKey = String(repeating: "0", count: 63) + "1"
    let desktopPrivateKey = String(repeating: "0", count: 63) + "2"
    let wrapperPrivateKey = String(repeating: "0", count: 63) + "3"
    let phoneKeypair = try NostrAgentKeypair(privateKeyHex: phonePrivateKey)
    let desktopKeypair = try NostrAgentKeypair(privateKeyHex: desktopPrivateKey)
    let envelope = AgentMessageEnvelope(
        conversationID: "home:apartment",
        area: "home",
        sender: .desktopClient,
        kind: .imageReference,
        text: "Screenshot reference from the desktop.",
        attachments: [
            AgentMessageAttachment(
                kind: .imageReference,
                name: "approval.png",
                contentType: "image/png",
                localReference: "clawdia://desktop/context/approval-image"
            )
        ],
        createdAt: 1_777_777_777
    )
    let draft = NostrEventDraft(
        pubkey: desktopKeypair.publicKeyHex,
        createdAt: 1_777_777_777,
        kind: NostrAgentEventFactory.ephemeralAgentMessageKind,
        tags: [
            ["p", phoneKeypair.publicKeyHex],
            ["app", "clawdia"],
            ["schema", AgentMessageEnvelope.schema],
            ["conversation", "home:apartment"],
            ["area", "home"]
        ],
        content: try encodeAgentEnvelope(envelope)
    )
    let outboxEvent = NostrOutboxEvent(
        draft: draft,
        relayURLs: [URL(string: "wss://relay.example.com")!],
        delivery: .requiresEncryptedGiftWrap
    )
    let sender = try NostrEncryptedAgentMessageSender(
        phonePrivateKeyHex: desktopPrivateKey,
        entropy: SequenceNostrEntropySource([
            Data(repeating: 9, count: 32),
            try dataFromHex(wrapperPrivateKey),
            Data(repeating: 10, count: 32)
        ])
    )
    let receiver = try NostrEncryptedAgentMessageReceiver(
        phonePrivateKeyHex: phonePrivateKey,
        expectedSenderPublicKeyHex: desktopKeypair.publicKeyHex
    )
    let repository = InMemoryChatMessageRepository()
    let store = DevModeStore(state: .preview, nostrMessageReceiver: receiver, chatMessageRepository: repository)

    let prepared = try sender.send(outboxEvent)
    let received = store.receiveNostrRelayEvent(prepared)

    try expect(received == envelope, "store should return the incoming desktop envelope")
    try expect(store.state.receivedAgentMessages == [envelope], "store should retain accepted incoming agent messages in phone memory")
    let persisted = try repository.loadActiveMessages(now: Date(timeIntervalSince1970: 1_777_777_800))
    try expect(persisted.map(\.text) == [envelope.text], "incoming desktop envelopes should be persisted into phone chat history")
    try expect(persisted.first?.deliveryState == .received, "incoming desktop envelopes should be marked received in local history")
    try expect(!store.state.isAgentTyping(conversationID: envelope.conversationID), "incoming desktop replies should clear the typing indicator")
}

func testPublishingSenderPublishesPreparedGiftWrap() throws {
    let phonePrivateKey = String(repeating: "0", count: 63) + "1"
    let desktopPrivateKey = String(repeating: "0", count: 63) + "2"
    let wrapperPrivateKey = String(repeating: "0", count: 63) + "3"
    let phoneKeypair = try NostrAgentKeypair(privateKeyHex: phonePrivateKey)
    let desktopKeypair = try NostrAgentKeypair(privateKeyHex: desktopPrivateKey)
    let relayURL = URL(string: "wss://relay.example.com")!
    let configuration = NostrAgentBridgeConfiguration(
        phonePublicKey: phoneKeypair.publicKeyHex,
        desktopPublicKey: desktopKeypair.publicKeyHex,
        relayURLs: [relayURL]
    )
    let chat = ChatPreview(title: "Apartment tasks", preview: "Package pickup is open.", time: "Now", area: .home)
    let outboxEvent = NostrAgentEventFactory(configuration: configuration)
        .queueChatMessage(text: "Can you check the package?", chat: chat, now: Date(timeIntervalSince1970: 1_777_777_777))
    let receipt = NostrRelayPublishReceipt(relayURL: relayURL, eventID: "pending", accepted: true, message: "")
    let publisher = RecordingNostrRelayPublisher(receipts: [receipt])
    let semaphore = DispatchSemaphore(value: 0)
    let receiptBox = NostrReceiptBox()
    let sender = try NostrPublishingAgentMessageSender(
        phonePrivateKeyHex: phonePrivateKey,
        relayPublisher: publisher,
        entropy: SequenceNostrEntropySource([
            Data(repeating: 1, count: 32),
            try dataFromHex(wrapperPrivateKey),
            Data(repeating: 4, count: 32)
        ]),
        receiptHandler: { receipts in
            receiptBox.set(receipts)
            semaphore.signal()
        }
    )

    let prepared = try sender.send(outboxEvent)
    guard semaphore.wait(timeout: .now() + 2) == .success else {
        throw VerificationFailure(description: "publishing sender should call the relay publisher")
    }

    try expect(publisher.publishedEventIDs() == [prepared.id], "publishing sender should publish the prepared gift wrap")
    try expect(receiptBox.get() == [receipt], "publishing sender should surface relay receipts")
}

func testNostrRelayOKResponseParsing() throws {
    let relayURL = URL(string: "wss://relay.example.com")!
    let eventID = String(repeating: "a", count: 64)

    let accepted = NostrRelayResponseParser.receipt(from: "[\"OK\",\"\(eventID)\",true,\"\"]", relayURL: relayURL)
    try expect(accepted?.eventID == eventID, "relay OK parser should retain the event id")
    try expect(accepted?.accepted == true, "relay OK parser should retain accepted=true")
    try expect(accepted?.relayURL == relayURL, "relay OK parser should retain the relay URL")

    let rejected = NostrRelayResponseParser.receipt(from: "[\"OK\",\"\(eventID)\",false,\"blocked: denied\"]", relayURL: relayURL)
    try expect(rejected?.accepted == false, "relay OK parser should retain accepted=false")
    try expect(rejected?.message == "blocked: denied", "relay OK parser should retain relay messages")
}

func testNostrBridgeCredentialsDeriveRuntimeConfiguration() throws {
    let phonePrivateKey = String(repeating: "0", count: 63) + "1"
    let desktopPrivateKey = String(repeating: "0", count: 63) + "2"
    let phoneKeypair = try NostrAgentKeypair(privateKeyHex: phonePrivateKey)
    let desktopKeypair = try NostrAgentKeypair(privateKeyHex: desktopPrivateKey)
    let relayURL = URL(string: "wss://relay.example.com")!
    let credentials = try NostrAgentBridgeCredentials(
        phonePrivateKeyHex: phonePrivateKey,
        desktopPublicKeyHex: desktopKeypair.publicKeyHex,
        relayURLs: [relayURL]
    )

    let configuration = try credentials.bridgeConfiguration()

    try expect(configuration.phonePublicKey == phoneKeypair.publicKeyHex, "credentials should derive the phone public key from the secure private key")
    try expect(configuration.desktopPublicKey == desktopKeypair.publicKeyHex, "credentials should retain the paired desktop public key")
    try expect(configuration.relayURLs == [relayURL], "credentials should retain paired relay URLs")
}

func testNostrDesktopPairingPayloadRoundTripsURI() throws {
    let desktopPrivateKey = String(repeating: "0", count: 63) + "2"
    let desktopKeypair = try NostrAgentKeypair(privateKeyHex: desktopPrivateKey)
    let relayURL = URL(string: "wss://relay.example.com")!
    let payload = try NostrDesktopPairingPayload(
        desktopPublicKeyHex: desktopKeypair.publicKeyHex,
        relayURLs: [relayURL],
        desktopName: "Mac mini"
    )

    let parsed = try NostrDesktopPairingPayload.parse(payload.pairingURI())

    try expect(parsed == payload, "desktop pairing payload should round-trip through the QR URI format")
}

func testStorePairsDesktopFromPairingPayload() throws {
    let desktopPrivateKey = String(repeating: "0", count: 63) + "2"
    let desktopKeypair = try NostrAgentKeypair(privateKeyHex: desktopPrivateKey)
    let relayURL = URL(string: "wss://relay.example.com")!
    let payload = try NostrDesktopPairingPayload(
        desktopPublicKeyHex: desktopKeypair.publicKeyHex,
        relayURLs: [relayURL],
        desktopName: "Mac mini"
    )
    let credentialStore = RecordingNostrBridgeCredentialStore()
    let semaphore = DispatchSemaphore(value: 0)
    let relayPublisher = RecordingNostrRelayPublisher(receipts: [
        NostrRelayPublishReceipt(relayURL: relayURL, eventID: "ack", accepted: true, message: "")
    ], onPublish: {
        semaphore.signal()
    })
    let store = DevModeStore(
        state: .preview,
        nostrCredentialStore: credentialStore,
        nostrEntropy: SequenceNostrEntropySource([try dataFromHex(String(repeating: "0", count: 63) + "1")]),
        nostrRelayPublisher: relayPublisher,
        phoneClientDisplayName: "Shadow iPhone",
        now: { Date(timeIntervalSince1970: 1_777_777_777) }
    )

    let didPair = try store.pairDesktop(with: payload.pairingURI())

    try expect(didPair, "store should accept a valid desktop pairing payload")
    try expect(store.desktopPairingStatus == .paired(displayName: "Mac mini"), "store should mark the desktop as paired")
    try expect(credentialStore.savedCredentials?.desktopPublicKeyHex == desktopKeypair.publicKeyHex, "pairing should persist the desktop public key")
    try expect(credentialStore.savedCredentials?.relayURLStrings == [relayURL.absoluteString], "pairing should persist relay URLs")
    try expect(credentialStore.savedCredentials?.desktopDisplayName == "Mac mini", "pairing should persist the desktop display name")
    guard let acknowledgement = store.state.preparedNostrRelayEvents.last else {
        throw VerificationFailure(description: "pairing should prepare a signed desktop acknowledgement event")
    }
    try expect(acknowledgement.kind == NostrDesktopPairingAcknowledgement.kind, "pairing should prepare a signed desktop acknowledgement event")
    try expect(acknowledgement.tags.contains(["p", desktopKeypair.publicKeyHex]), "pairing acknowledgement should be addressed to the desktop public key")
    try expect(acknowledgement.content.contains("Shadow iPhone"), "pairing acknowledgement should identify the phone")
    guard semaphore.wait(timeout: .now() + 2) == .success else {
        throw VerificationFailure(description: "pairing should publish the signed desktop acknowledgement event")
    }
    try expect(relayPublisher.publishedEventIDs() == [acknowledgement.id], "pairing acknowledgement should be sent to the configured relay publisher")
}

func testStoreReportsFailedDesktopPairing() throws {
    let store = DevModeStore(state: .preview)

    let didPair = store.pairDesktop(with: "not-a-clawdia-pairing-code")

    try expect(!didPair, "store should reject an invalid desktop pairing payload")
    switch store.desktopPairingStatus {
    case .failed(let message):
        try expect(message.contains("desktop pairing code"), "failed pairing should include a useful retry message")
    default:
        throw VerificationFailure(description: "failed pairing should update desktop pairing status")
    }
}

func testAgentEnvelopeCarriesReferencesWithoutFileBytes() throws {
    let envelope = AgentMessageEnvelope(
        conversationID: "home:apartment",
        area: "home",
        sender: .desktopClient,
        kind: .diffReference,
        text: "I found a config diff to review.",
        attachments: [
            AgentMessageAttachment(
                kind: .diffReference,
                name: "settings.diff",
                contentType: "text/x-diff",
                localReference: "clawdia://desktop/context/settings-diff"
            ),
            AgentMessageAttachment(
                kind: .imageReference,
                name: "preview.png",
                contentType: "image/png",
                localReference: "clawdia://desktop/context/preview-image"
            )
        ],
        createdAt: 1_777_777_777
    )

    try expect(envelope.attachments.count == 2, "agent envelopes should carry multiple context references")
    try expect(envelope.attachments.allSatisfy { $0.localReference?.hasPrefix("clawdia://") == true }, "agent envelopes should reference local context instead of embedding file bytes")
}

func testLocalConnectionRequestShape() throws {
    let request = URLRequest.clawdiaHealthRequest(endpoint: .localhost(port: 8787), timeout: 2)

    try expect(request?.url?.absoluteString == "http://127.0.0.1:8787/health", "localhost health request should target the local Clawdia health route")
    try expect(request?.httpMethod == "GET", "localhost health request should use GET")
    try expect(request?.value(forHTTPHeaderField: "Accept") == "application/json", "localhost health request should accept JSON")
}

do {
    try testSharedKernel()
    try testDesignSystemTokens()
    try testFeatureCatalog()
    try testProductionStateUsesRealAgentThreads()
    try testIPhoneDataConnectionsDefaultToProductionOptions()
    try testStoreRequestsIPhoneDataConnectionForDesktopAnalysis()
    try await testSystemProviderTreatsMissingICloudIdentityAsUnavailable()
    try testStoreDeletesChatAndPersistedConversation()
    try testStoreDeletesLifeAreaAndPersistedAreaMessages()
    try testStoreDeletesSelectedMessagesOnly()
    try testStoredChatMessagesRespectOneHourTTL()
    try testAppFlowAreaConfiguration()
    try testOnboardingCompletionPersistsSelectedAreas()
    try testSignOutReturnsToFreshOnboardingAndClearsPairing()
    try testAppFlowCustomAreaCreationAndFiltering()
    try testRuntimeModeDefaultsToProductionAndUsesFlags()
    try testPreviewChatsAreScopedToAreas()
    try testAreaChatNavigationKeepsAreaRouteBehindChat()
    try testCalendarCurrentDateResolver()
    try testNostrAgentEnvelopeDraftShape()
    try testStoreQueuesNostrEventOnChatSend()
    try testStorePreparesRelayEventWhenSenderIsConfigured()
    try testPreparedRelayEventEncodesNIP01ClientFrame()
    try testRelaySubscriptionEncodesNIP01Request()
    try testNostrRelayEventResponseParsing()
    try testNIP44OfficialVector()
    try testEncryptedNostrSenderPreparesGiftWrap()
    try testEncryptedNostrReceiverUnwrapsDesktopEnvelope()
    try testStoreStoresIncomingNostrEnvelopeInPhoneMemory()
    try testPublishingSenderPublishesPreparedGiftWrap()
    try testNostrRelayOKResponseParsing()
    try testNostrBridgeCredentialsDeriveRuntimeConfiguration()
    try testNostrDesktopPairingPayloadRoundTripsURI()
    try testStorePairsDesktopFromPairingPayload()
    try testStoreReportsFailedDesktopPairing()
    try testAgentEnvelopeCarriesReferencesWithoutFileBytes()
    try testLocalConnectionRequestShape()
    print("Clawdia verification tests passed")
} catch {
    fputs("Clawdia verification tests failed: \(error)\n", stderr)
    exit(1)
}
