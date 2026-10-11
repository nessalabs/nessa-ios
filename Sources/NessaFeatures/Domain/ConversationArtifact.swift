import Foundation

/// A file supplied by an adapter. Missing content remains browseable as metadata.
public struct NessaFileAttachment: Decodable, Sendable, Equatable {
  public let name: String
  public let mimeType: String
  public let data: Data?
  public init(name: String, mimeType: String, data: Data? = nil) {
    self.name = name
    self.mimeType = mimeType
    self.data = data
  }
}

public struct ConversationArtifact: Identifiable, Sendable, Equatable {
  public enum Content: Sendable, Equatable {
    case image(NessaImageAttachment)
    case file(NessaFileAttachment)
  }
  public let id: String
  public let turnID: String
  public let content: Content

  /// Preserve occurrences and conversation order, including repeated attachments.
  public static func collect(from turns: [NessaTurn]) -> [Self] {
    turns.flatMap { turn in
      let images = (turn.attachments ?? []).enumerated().map { index, image in
        Self(id: "\(turn.id):image:\(index)", turnID: turn.id, content: .image(image))
      }
      let files = (turn.files ?? []).enumerated().map { index, file in
        Self(id: "\(turn.id):file:\(index)", turnID: turn.id, content: .file(file))
      }
      return images + files
    }
  }
}
