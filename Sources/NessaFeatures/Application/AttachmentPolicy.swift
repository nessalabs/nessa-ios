import Foundation

public struct AttachmentPolicy: Sendable {
  public let allowsFiles: Bool
  public let maximumCount: Int
  public let maximumFileBytes: Int
  public let maximumTotalBytes: Int
  public static let development = Self(
    allowsFiles: true, maximumCount: 8,
    maximumFileBytes: 64 * 1024 * 1024, maximumTotalBytes: 64 * 1024 * 1024)
  public static let nessa = Self(
    allowsFiles: false, maximumCount: 8,
    maximumFileBytes: 5 * 1024 * 1024, maximumTotalBytes: 10 * 1024 * 1024)
  public func validate(_ attachments: [DraftAttachment]) throws {
    guard allowsFiles || attachments.allSatisfy(\.isImage) else {
      throw NessaGatewayError.rejected(
        "This connection supports photos. Other files aren’t supported yet.")
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
