import Foundation

public struct AttachmentPolicy: Sendable {
  public let allowsFiles: Bool
  public let maximumCount: Int
  public let maximumFileBytes: Int
  public let maximumTotalBytes: Int
  public let maximumImageBytes: Int?
  public let maximumImagesBytes: Int?
  public init(
    allowsFiles: Bool, maximumCount: Int, maximumFileBytes: Int, maximumTotalBytes: Int,
    maximumImageBytes: Int? = nil, maximumImagesBytes: Int? = nil
  ) {
    self.allowsFiles = allowsFiles
    self.maximumCount = maximumCount
    self.maximumFileBytes = maximumFileBytes
    self.maximumTotalBytes = maximumTotalBytes
    self.maximumImageBytes = maximumImageBytes
    self.maximumImagesBytes = maximumImagesBytes
  }
  public static let development = Self(
    allowsFiles: true, maximumCount: 8,
    maximumFileBytes: 64 * 1024 * 1024, maximumTotalBytes: 64 * 1024 * 1024)
  public static let nessa = Self(
    allowsFiles: true, maximumCount: 8,
    maximumFileBytes: AttachmentReferences.maximumFileBytes,
    maximumTotalBytes: AttachmentReferences.maximumFileBytes,
    maximumImageBytes: 5 * 1024 * 1024, maximumImagesBytes: 10 * 1024 * 1024)
  public func validate(_ attachments: [DraftAttachment]) throws {
    guard allowsFiles || attachments.allSatisfy(\.isImage) else {
      throw NessaGatewayError.rejected(
        "This connection supports photos. Other files aren’t supported yet.")
    }
    let images = attachments.filter(\.isImage)
    guard images.allSatisfy({ $0.data.count <= (maximumImageBytes ?? maximumFileBytes) }),
      images.reduce(0, { $0 + $1.data.count }) <= (maximumImagesBytes ?? maximumTotalBytes)
    else {
      throw NessaGatewayError.rejected("Choose photos up to 5 MB each and 10 MB together.")
    }
    guard attachments.count <= maximumCount,
      attachments.allSatisfy({ !$0.data.isEmpty && $0.data.count <= maximumFileBytes }),
      attachments.reduce(0, { $0 + $1.data.count }) <= maximumTotalBytes
    else {
      throw NessaGatewayError.rejected(
        "Choose up to \(maximumCount) attachments, at most \(maximumFileBytes / 1024 / 1024) MB each and \(maximumTotalBytes / 1024 / 1024) MB total."
      )
    }
  }
}
