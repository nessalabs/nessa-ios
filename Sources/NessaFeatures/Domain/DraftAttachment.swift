import Foundation

public struct DraftAttachment: Identifiable, Sendable, Equatable {
  public let id: UUID
  public let name: String
  public let mimeType: String
  public let data: Data
  public init(id: UUID = UUID(), name: String, mimeType: String, data: Data) {
    self.id = id
    self.name = name
    self.mimeType = mimeType
    self.data = data
  }
  public var isImage: Bool {
    ["image/jpeg", "image/png", "image/gif", "image/webp"].contains(mimeType)
  }
}
public struct NessaImageAttachment: Codable, Sendable, Equatable {
  public let digest: String
  public let mimeType: String
  public let size: Int
}
