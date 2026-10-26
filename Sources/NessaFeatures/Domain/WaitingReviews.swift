import Foundation

/// The permission reviews waiting on the person, as the gateway announces them over the
/// connection: each announcement replaces the last. It names the chats a review waits in
/// even when the phone has never read them. It is not every review that waits: the gateway
/// names a bounded set, dropping the oldest, so a review a chat's view holds may still wait
/// though no announcement names it.
public struct WaitingReviews: Decodable, Sendable, Equatable {
  public struct Review: Decodable, Sendable, Equatable {
    public let conversationId: String
    public let executionId: String
    public let permissionId: String
    public let tool: String
    /// The chat's name when the gateway announced it, if it has one.
    public let title: String?
    /// Whether this is the review a chat's view holds as `permission`.
    public func matches(_ permission: NessaPermission) -> Bool {
      permission.permissionId == permissionId && permission.executionId == executionId
    }
    var key: String { Self.key(conversationId, executionId, permissionId) }
    static func key(_ conversation: String, _ permission: NessaPermission) -> String {
      key(conversation, permission.executionId, permission.permissionId)
    }
    private static func key(_ conversation: String, _ execution: String, _ permission: String)
      -> String
    { [conversation, execution, permission].joined(separator: "\u{0}") }
  }
  /// Oldest first.
  public let reviews: [Review]

  public var conversationIDs: Set<String> { Set(reviews.map(\.conversationId)) }
  public init(reviews: [Review]) { self.reviews = reviews }
}
