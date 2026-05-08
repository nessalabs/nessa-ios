import Foundation

public struct NostrAgentBridgeConfiguration: Equatable, Sendable {
    public let phonePublicKey: String
    public let desktopPublicKey: String
    public let relayURLs: [URL]

    public init(phonePublicKey: String, desktopPublicKey: String, relayURLs: [URL]) {
        self.phonePublicKey = phonePublicKey
        self.desktopPublicKey = desktopPublicKey
        self.relayURLs = relayURLs
    }

    public static let preview = NostrAgentBridgeConfiguration(
        phonePublicKey: "2f8d3f9240c7d7fc5f27b0d7f2fbc17ef03a27e42091301a80b2df911d010001",
        desktopPublicKey: "5ce3e2b449df037bd49d19931f7f5f8f1eddbd0d64f2892970f642f047fb0002",
        relayURLs: []
    )
}

public struct NostrEventDraft: Equatable, Sendable {
    public let pubkey: String
    public let createdAt: Int
    public let kind: Int
    public let tags: [[String]]
    public let content: String

    public init(pubkey: String, createdAt: Int, kind: Int, tags: [[String]], content: String) {
        self.pubkey = pubkey
        self.createdAt = createdAt
        self.kind = kind
        self.tags = tags
        self.content = content
    }
}

public struct NostrOutboxEvent: Equatable, Sendable {
    public let id: UUID
    public let draft: NostrEventDraft
    public let relayURLs: [URL]
    public let delivery: NostrOutboxDelivery

    public init(
        id: UUID = UUID(),
        draft: NostrEventDraft,
        relayURLs: [URL],
        delivery: NostrOutboxDelivery
    ) {
        self.id = id
        self.draft = draft
        self.relayURLs = relayURLs
        self.delivery = delivery
    }
}

public enum NostrOutboxDelivery: Equatable, Sendable {
    case requiresEncryptedGiftWrap
}

public struct NostrPreparedRelayEvent: Encodable, Equatable, Sendable {
    public let id: String
    public let pubkey: String
    public let createdAt: Int
    public let kind: Int
    public let tags: [[String]]
    public let content: String
    public let signature: String
    public let relayURLs: [URL]

    private enum CodingKeys: String, CodingKey {
        case id
        case pubkey
        case createdAt = "created_at"
        case kind
        case tags
        case content
        case signature = "sig"
    }

    public init(
        id: String,
        pubkey: String,
        createdAt: Int,
        kind: Int,
        tags: [[String]],
        content: String,
        signature: String,
        relayURLs: [URL]
    ) {
        self.id = id
        self.pubkey = pubkey
        self.createdAt = createdAt
        self.kind = kind
        self.tags = tags
        self.content = content
        self.signature = signature
        self.relayURLs = relayURLs
    }

    public func relayClientMessageJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(NostrRelayClientEventMessage(event: self))
        guard let json = String(data: data, encoding: .utf8) else {
            throw NostrRelayClientMessageError.utf8EncodingFailed
        }
        return json
    }
}

public struct NostrRelaySubscription: Equatable, Sendable {
    public let id: String
    public let relayURLs: [URL]
    public let recipientPublicKey: String
    public let kinds: [Int]

    public init(
        id: String = "clawdia-agent-inbox",
        relayURLs: [URL],
        recipientPublicKey: String,
        kinds: [Int] = [1_059]
    ) {
        self.id = id
        self.relayURLs = relayURLs
        self.recipientPublicKey = recipientPublicKey
        self.kinds = kinds
    }

    public func relayClientMessageJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(NostrRelayClientSubscriptionMessage(subscription: self))
        guard let json = String(data: data, encoding: .utf8) else {
            throw NostrRelayClientMessageError.utf8EncodingFailed
        }
        return json
    }
}

public protocol NostrAgentMessageSending {
    @discardableResult
    func send(_ event: NostrOutboxEvent) throws -> NostrPreparedRelayEvent
}

public protocol NostrAgentMessageReceiving {
    func receive(_ event: NostrPreparedRelayEvent) throws -> AgentMessageEnvelope
}

public enum NostrRelayClientMessageError: Error {
    case utf8EncodingFailed
}

private struct NostrRelayClientEventMessage: Encodable {
    let event: NostrPreparedRelayEvent

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode("EVENT")
        try container.encode(event)
    }
}

private struct NostrRelayClientSubscriptionMessage: Encodable {
    let subscription: NostrRelaySubscription

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode("REQ")
        try container.encode(subscription.id)
        try container.encode(NostrRelayFilter(kinds: subscription.kinds, recipientPublicKeys: [subscription.recipientPublicKey]))
    }
}

private struct NostrRelayFilter: Encodable {
    let kinds: [Int]
    let recipientPublicKeys: [String]

    private enum CodingKeys: String, CodingKey {
        case kinds
        case recipientPublicKeys = "#p"
    }
}

public struct NostrAgentEventFactory: Sendable {
    public static let ephemeralAgentMessageKind = 24_133

    public let configuration: NostrAgentBridgeConfiguration

    public init(configuration: NostrAgentBridgeConfiguration = .preview) {
        self.configuration = configuration
    }

    public func makeChatMessageDraft(text: String, chat: ChatPreview, now: Date = Date()) -> NostrEventDraft {
        let createdAt = Int(now.timeIntervalSince1970)
        let envelope = AgentMessageEnvelope(
            conversationID: chat.id.uuidString,
            area: chat.area.rawValue,
            sender: .phone,
            kind: .chatMessage,
            text: text,
            createdAt: createdAt
        )
        return NostrEventDraft(
            pubkey: configuration.phonePublicKey,
            createdAt: createdAt,
            kind: Self.ephemeralAgentMessageKind,
            tags: [
                ["p", configuration.desktopPublicKey],
                ["app", "clawdia"],
                ["schema", AgentMessageEnvelope.schema],
                ["conversation", chat.id.uuidString],
                ["area", chat.area.rawValue]
            ],
            content: encode(envelope)
        )
    }

    public func queueChatMessage(text: String, chat: ChatPreview, now: Date = Date()) -> NostrOutboxEvent {
        NostrOutboxEvent(
            draft: makeChatMessageDraft(text: text, chat: chat, now: now),
            relayURLs: configuration.relayURLs,
            delivery: .requiresEncryptedGiftWrap
        )
    }

    private func encode(_ envelope: AgentMessageEnvelope) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(envelope),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }
}
