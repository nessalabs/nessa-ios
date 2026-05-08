import Foundation

public enum AgentMessageKind: String, Codable, Equatable, Sendable {
    case chatMessage
    case fileReference
    case diffReference
    case imageReference
}

public enum AgentMessageSender: String, Codable, Equatable, Sendable {
    case phone
    case desktopClient
    case externalAgent
}

public struct AgentMessageAttachment: Codable, Equatable, Sendable {
    public let id: UUID
    public let kind: AgentMessageKind
    public let name: String
    public let contentType: String?
    public let localReference: String?

    public init(
        id: UUID = UUID(),
        kind: AgentMessageKind,
        name: String,
        contentType: String? = nil,
        localReference: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.contentType = contentType
        self.localReference = localReference
    }
}
public struct AgentMessageEnvelope: Codable, Equatable, Sendable {
    public static let schema = "com.clawdia.agent.message.v1"

    public let schema: String
    public let id: UUID
    public let conversationID: String
    public let area: String
    public let sender: AgentMessageSender
    public let kind: AgentMessageKind
    public let text: String
    public let attachments: [AgentMessageAttachment]
    public let createdAt: Int

    public init(
        id: UUID = UUID(),
        conversationID: String,
        area: String,
        sender: AgentMessageSender,
        kind: AgentMessageKind,
        text: String,
        attachments: [AgentMessageAttachment] = [],
        createdAt: Int,
        schema: String = AgentMessageEnvelope.schema
    ) {
        self.schema = schema
        self.id = id
        self.conversationID = conversationID
        self.area = area
        self.sender = sender
        self.kind = kind
        self.text = text
        self.attachments = attachments
        self.createdAt = createdAt
    }
}
