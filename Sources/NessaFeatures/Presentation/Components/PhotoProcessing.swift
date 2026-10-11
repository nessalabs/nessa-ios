import Foundation
import ImageIO
import UniformTypeIdentifiers

/// ImageIO downsamples before decoding; work stays off the main actor.
enum PhotoProcessing {
  static func thumbnail(_ data: Data, maximumDimension: Int) async -> CGImage? {
    await Task.detached(priority: .userInitiated) {
      guard
        let source = CGImageSourceCreateWithData(
          data as CFData,
          [kCGImageSourceShouldCache: false] as CFDictionary)
      else { return nil }
      return CGImageSourceCreateThumbnailAtIndex(
        source, 0,
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
          kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary)
    }.value
  }
  static func prepare(_ data: Data, name: String) async throws -> DraftAttachment {
    try Task.checkCancellation()
    guard !data.isEmpty, data.count <= 64 * 1024 * 1024,
      let image = await thumbnail(data, maximumDimension: 2048)
    else {
      throw NessaGatewayError.rejected(
        "This photo could not be loaded. Choose a photo under 64 MB.")
    }
    try Task.checkCancellation()
    return try await Task.detached(priority: .userInitiated) {
      let output = NSMutableData()
      guard
        let destination = CGImageDestinationCreateWithData(
          output, UTType.jpeg.identifier as CFString, 1, nil)
      else {
        throw NessaGatewayError.rejected("This photo could not be prepared.")
      }
      CGImageDestinationAddImage(
        destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
      guard CGImageDestinationFinalize(destination), output.length <= 5 * 1024 * 1024 else {
        throw NessaGatewayError.rejected("This photo is too large to send.")
      }
      return DraftAttachment(name: name, mimeType: "image/jpeg", data: output as Data)
    }.value
  }
  static func loadFile(_ url: URL) async throws -> DraftAttachment {
    let attachment = try await Task.detached(priority: .userInitiated) {
      let access = url.startAccessingSecurityScopedResource()
      defer { if access { url.stopAccessingSecurityScopedResource() } }
      let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
      guard let size = values.fileSize, size > 0, size <= 64 * 1024 * 1024 else {
        throw NessaGatewayError.rejected("Choose files no larger than 64 MB.")
      }
      return (
        DraftAttachment(
          name: url.lastPathComponent,
          mimeType: values.contentType?.preferredMIMEType ?? "application/octet-stream",
          data: try Data(contentsOf: url)), values.contentType?.conforms(to: .image) == true
      )
    }.value
    if attachment.1 || attachment.0.isImage {
      return try await prepare(attachment.0.data, name: attachment.0.name)
    }
    return attachment.0
  }
}
