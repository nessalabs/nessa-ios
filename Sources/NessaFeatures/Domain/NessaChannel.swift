import Foundation

/// A channel as the gateway lists it: a named place a conversation belongs to, whose agents
/// work in its folder. The default channel's id is `default`.
public struct NessaChannel: Codable, Identifiable, Sendable, Equatable, Hashable {
  public var id: String { channelId }
  public let channelId: String
  public let name: String
  public let folder: String
  public init(channelId: String, name: String, folder: String) {
    self.channelId = channelId
    self.name = name
    self.folder = folder
  }
  public static let defaultID = "default"
  public var isDefault: Bool { channelId == Self.defaultID }
}

/// One page of `channel.list`.
public struct NessaChannelPage: Codable, Sendable, Equatable {
  public let channels: [NessaChannel]
  public let complete: Bool
  public let cursor: String?
}
