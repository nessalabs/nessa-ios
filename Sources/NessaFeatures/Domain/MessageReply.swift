import Foundation

public struct MessageReply: Equatable, Sendable {
  public let id: String
  public let author: String
  public let text: String
}
