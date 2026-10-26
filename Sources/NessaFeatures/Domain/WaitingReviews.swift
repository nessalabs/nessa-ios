import Foundation

/// The permission reviews waiting on the person, as the gateway announces them over the
/// connection: each announcement replaces the last, and an empty one means none wait. It
/// names the chats a review waits in even when the phone has never read them.
public struct WaitingReviews: Decodable, Sendable, Equatable {
  public struct Review: Decodable, Sendable, Equatable {
    public let conversationId: String
    public let executionId: String
    public let permissionId: String
    public let tool: String
    /// The chat's name when the gateway announced it, if it has one.
    public let title: String?
  }
  /// Oldest first.
  public let reviews: [Review]

  /// The gateway names at most this many. A full set may leave newer reviews out, so it is
  /// not a whole answer to "what waits".
  public static let announced = 128
  public var complete: Bool { reviews.count < Self.announced }
  public var conversationIDs: Set<String> { Set(reviews.map(\.conversationId)) }
  public init(reviews: [Review]) { self.reviews = reviews }
}
