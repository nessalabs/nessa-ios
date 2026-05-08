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

func testAppFlowAreaConfiguration() throws {
    var state = MockAppState.preview

    state.configureInitialAreas([.personal, .work])

    try expect(state.folders.map(\.id) == [.personal, .work], "onboarding area selection should keep only chosen built-in areas")
    try expect(state.chats.allSatisfy { [.personal, .work].contains($0.area) }, "onboarding area selection should keep only chats for chosen areas")
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
    let store = DevModeStore(state: state, nostrMessageSender: sender)

    _ = store.sendChatMessage("Can you send this over Nostr?", in: chat)

    try expect(sender.sentEvents.count == 1, "configured Nostr senders should receive chat outbox events")
    try expect(store.state.preparedNostrRelayEvents == [preparedEvent], "prepared relay events should stay in phone memory")
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
    try testAppFlowAreaConfiguration()
    try testAppFlowCustomAreaCreationAndFiltering()
    try testPreviewChatsAreScopedToAreas()
    try testAreaChatNavigationKeepsAreaRouteBehindChat()
    try testCalendarCurrentDateResolver()
    try testNostrAgentEnvelopeDraftShape()
    try testStoreQueuesNostrEventOnChatSend()
    try testStorePreparesRelayEventWhenSenderIsConfigured()
    try testPreparedRelayEventEncodesNIP01ClientFrame()
    try testNIP44OfficialVector()
    try testEncryptedNostrSenderPreparesGiftWrap()
    try testNostrRelayOKResponseParsing()
    try testAgentEnvelopeCarriesReferencesWithoutFileBytes()
    try testLocalConnectionRequestShape()
    print("Clawdia verification tests passed")
} catch {
    fputs("Clawdia verification tests failed: \(error)\n", stderr)
    exit(1)
}
