import Foundation

public enum ChatMessageDeliveryState: String, Codable, Equatable, Sendable {
    case sending
    case sent
    case failed
    case received
}

public struct StoredChatMessage: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let conversationID: String
    public let area: String
    public let sender: AgentMessageSender
    public let text: String
    public let createdAt: Date
    public let expiresAt: Date
    public var deliveryState: ChatMessageDeliveryState

    public init(
        id: UUID = UUID(),
        conversationID: String,
        area: String,
        sender: AgentMessageSender,
        text: String,
        createdAt: Date,
        expiresAt: Date,
        deliveryState: ChatMessageDeliveryState
    ) {
        self.id = id
        self.conversationID = conversationID
        self.area = area
        self.sender = sender
        self.text = text
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.deliveryState = deliveryState
    }

    public func isExpired(now: Date) -> Bool {
        expiresAt <= now
    }
}
