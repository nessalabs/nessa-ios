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
public struct NessaStoredAttachment: Codable, Sendable, Equatable {
  public let digest: String
  public let mimeType: String
  public let size: Int
}

/// A stored non-image input retains its original name across send recovery.
public struct NessaUploadedFile: Codable, Sendable, Equatable {
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.digest == rhs.digest && lhs.mimeType == rhs.mimeType && lhs.size == rhs.size
      && lhs.name.utf8.elementsEqual(rhs.name.utf8)
  }
  public let digest: String
  public let mimeType: String
  public let size: Int
  public let name: String
  public init(digest: String, mimeType: String, size: Int, name: String) {
    self.digest = digest
    self.mimeType = mimeType
    self.size = size
    self.name = name
  }
  init(_ stored: NessaStoredAttachment, name: String) {
    self.init(digest: stored.digest, mimeType: stored.mimeType, size: stored.size, name: name)
  }
}
/// Phone-side reference validation, shared by both durable send paths.
enum AttachmentReferences {
  static let maximumFileBytes = 64 * 1024 * 1024
  static let imageTypes = ["image/png", "image/jpeg", "image/gif", "image/webp"]
  static func digest(_ value: String) -> Bool {
    value.hasPrefix("sha256:") && value.utf8.count == 71
      && value.dropFirst(7).utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
  }
  static func mediaType(_ value: String) -> Bool {
    let parts = value.split(separator: "/", omittingEmptySubsequences: false)
    let initial: (UInt8) -> Bool = { (97...122).contains($0) || (48...57).contains($0) }
    return value.utf8.count <= 127 && parts.count == 2
      && parts.allSatisfy { part in
        guard let first = part.utf8.first, initial(first) else { return false }
        return part.utf8.allSatisfy { initial($0) || Array("!#$&^_.+-".utf8).contains($0) }
      }
  }
  static func valid(images: [NessaStoredAttachment], uploads: [NessaUploadedFile]) -> Bool {
    guard images.count + uploads.count <= 8,
      images.allSatisfy({
        $0.size > 0 && $0.size <= 5 * 1024 * 1024 && imageTypes.contains($0.mimeType)
          && digest($0.digest)
      }),
      uploads.allSatisfy({
        $0.size > 0 && $0.size <= maximumFileBytes && digest($0.digest) && mediaType($0.mimeType)
          && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          && $0.name.utf8.count <= 255
          && !$0.name.unicodeScalars.contains(where: {
            ($0.value < 0x20 || (0x7f...0x9f).contains($0.value)) || $0 == "/" || $0 == "\\"
          })
      })
    else { return false }
    return images.reduce(0, { $0 + $1.size }) <= 10 * 1024 * 1024
      && uploads.reduce(0, { $0 + $1.size }) <= maximumFileBytes
  }
}
