import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import NessaFeatures

@Test
func photoPreparationDownsamplesBeforeSendingAndPreservesAspectRatio() async throws {
  let context = try #require(
    CGContext(
      data: nil, width: 4000, height: 2000,
      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
  context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
  context.fill(CGRect(x: 0, y: 0, width: 4000, height: 2000))
  let original = try #require(context.makeImage())
  let bytes = NSMutableData()
  let destination = try #require(
    CGImageDestinationCreateWithData(
      bytes,
      UTType.png.identifier as CFString, 1, nil))
  CGImageDestinationAddImage(destination, original, nil)
  #expect(CGImageDestinationFinalize(destination))
  let prepared = try await PhotoProcessing.prepare(bytes as Data, name: "Landscape.jpg")
  #expect(prepared.mimeType == "image/jpeg")
  let source = try #require(CGImageSourceCreateWithData(prepared.data as CFData, nil))
  let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
  #expect(image.width == 2048)
  #expect(image.height == 1024)
  try AttachmentPolicy.nessa.validate([prepared])
  await #expect(throws: NessaGatewayError.self) {
    _ = try await PhotoProcessing.prepare(Data([1, 2, 3]), name: "invalid.jpg")
  }
}

@Test
func mockPhotoCanBeReadAfterAttachmentOnlyMessage() async throws {
  let repository = MockRepository()
  let service = MessagingService(repository: repository)
  try await service.connect(address: "mock://photos", credential: "", instance: "test")
  let id = try await service.create(agent: nil)
  let bytes = Data([1, 2, 3, 4])
  try await service.send(
    "", attachments: [DraftAttachment(name: "photo.jpg", mimeType: "image/jpeg", data: bytes)],
    conversationID: id)
  let view = try await service.read(id)
  let reference = try #require(view.messages.first?.attachments?.first)
  #expect(try await service.imageData(for: reference) == bytes)
}

@Test
func imageCacheSurvivesRecreationButIsScopedToIdentity() async throws {
  let scope = UUID().uuidString
  let cache = AttachmentImageCache(scope: scope)
  let digest = "sha256:" + String(repeating: "a", count: 64)
  let bytes = Data([1, 2, 3])
  await cache.store(bytes, digest: digest)
  #expect(await AttachmentImageCache(scope: scope).read(digest) == bytes)
  #expect(await AttachmentImageCache(scope: scope + "other").read(digest) == nil)
  #expect(await cache.read("sha256:../../private") == nil)
}

@Test
func liveAttachmentPolicyRejectsFilesAndOversizeImagesBeforeUpload() throws {
  let file = DraftAttachment(name: "notes.txt", mimeType: "text/plain", data: Data([1]))
  #expect(throws: NessaGatewayError.self) { try AttachmentPolicy.nessa.validate([file]) }
  let large = DraftAttachment(
    name: "large.jpg", mimeType: "image/jpeg", data: Data(count: 5 * 1024 * 1024 + 1))
  #expect(throws: NessaGatewayError.self) { try AttachmentPolicy.nessa.validate([large]) }
  try AttachmentPolicy.development.validate([file])
}

@Test
func imageFileImportConvertsTIFFForGateway() async throws {
  let context = try #require(
    CGContext(
      data: nil, width: 24, height: 16, bitsPerComponent: 8,
      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
  let image = try #require(context.makeImage())
  let url = FileManager.default.temporaryDirectory.appendingPathComponent(
    UUID().uuidString + ".tiff")
  defer { try? FileManager.default.removeItem(at: url) }
  let destination = try #require(
    CGImageDestinationCreateWithURL(url as CFURL, UTType.tiff.identifier as CFString, 1, nil))
  CGImageDestinationAddImage(destination, image, nil)
  #expect(CGImageDestinationFinalize(destination))
  let prepared = try await PhotoProcessing.loadFile(url)
  #expect(prepared.mimeType == "image/jpeg")
  try AttachmentPolicy.nessa.validate([prepared])
  #expect(await PhotoProcessing.thumbnail(prepared.data, maximumDimension: 100) != nil)
}
