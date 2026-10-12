import Foundation

/// Replacement publications for the live UI. Retained physical replication is a separate port.
public protocol ConversationFollowing: Sendable {
  func follow(_ conversationID: String?, after: ConversationCursor?) async throws
    -> AsyncThrowingStream<ConversationUpdate, Error>
}

public enum ConversationUpdate: Sendable {
  case list(NessaConversationList)
  case view(ConversationCursor, NessaConversationView)
}

public struct ConversationCursor: Codable, Equatable, Sendable {
  public let incarnation: String
  public let position: String
  public var offset: UInt64 { UInt64(position)! }
  public init(incarnation: String, position: String) throws {
    guard !incarnation.isEmpty, incarnation.unicodeScalars.count <= 128,
      !position.isEmpty, position.utf8.allSatisfy({ (48...57).contains($0) }),
      position == "0" || position.first != "0", UInt64(position) != nil
    else { throw NessaGatewayError.invalidFrame }
    self.incarnation = incarnation
    self.position = position
  }
  private enum CodingKeys: String, CodingKey { case incarnation, position }
  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      incarnation: values.decode(String.self, forKey: .incarnation),
      position: values.decode(String.self, forKey: .position))
  }
}

public struct ConversationFeedEnded: Error, LocalizedError, Sendable {
  public enum Reason: String, Decodable, Sendable {
    case lagging, refused
    case sourceClosed = "source_closed"
    case tooLarge = "too_large"
  }
  public let reason: Reason
  public let code: String?
  public var errorDescription: String? {
    switch reason {
    case .lagging, .sourceClosed: "Live updates stopped. Reconnect to catch up."
    case .refused: "The gateway refused live updates for this chat."
    case .tooLarge: "This chat is too large for a live update."
    }
  }
}
