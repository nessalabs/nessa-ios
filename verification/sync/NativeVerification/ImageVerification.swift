import CoreGraphics
import Foundation
import ImageIO
import NessaFeatures
import UniformTypeIdentifiers

/// Exercise phone model selection, upload, history and local recovery.
/// Generates a public test pattern; never reads a user's photo library.
enum ImageVerification {
  @MainActor static func run(endpoint: String, credentialFile: String) async throws {
    let credential = try String(contentsOfFile: credentialFile, encoding: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let journal = PhoneCommandJournal(store: PhoneCommandStore(root: root))
    let client = NessaGatewayClient(journal: journal)
    let service = MessagingService(repository: client, directory: client)
    let model = MessagesViewModel(
      service: service, credentials: InMemoryCredentialStore(),
      preferences: InMemoryChatPreferences())
    var createdID: String?
    do {
      await model.connect(address: endpoint, credential: credential, instance: "phone-image-check")
      guard model.connected else { throw NessaGatewayError.disconnected }
      guard let id = await model.create() else {
        throw NessaGatewayError.rejected(model.error ?? "Create failed")
      }
      createdID = id
      guard try await service.pendingCommands().isEmpty, model.pendingCommands.isEmpty else {
        throw NessaGatewayError.rejected("Creation did not resolve its pending command")
      }
      let runtime = try await service.read(id).runtime
      guard let profile = model.agentProfiles.first(where: { $0.id == runtime?.agent }),
        profile.models.contains(where: { $0.id == runtime?.model && $0.supportsImages })
      else { throw NessaGatewayError.imageInputUnsupported }
      print("PASS: new phone chat selected an advertised image-capable model")
      let photo = DraftAttachment(
        name: "Synthetic-pattern.png", mimeType: "image/png", data: try pattern())
      let identity = MessageCommandIdentity()
      guard
        await model.send(
          "Describe the colors and shapes in this image briefly. Do not use tools.",
          attachments: [photo], to: id, identity: identity)
      else {
        throw NessaGatewayError.rejected(model.error ?? "Photo send failed")
      }
      guard try await service.pendingCommands().isEmpty, model.pendingCommands.isEmpty else {
        throw NessaGatewayError.rejected("Photo send did not resolve its pending command")
      }
      print("PASS: app photo submission, upload and durable command resolution")
      var completed = false
      for _ in 0..<120 {
        let view = try await service.read(id)
        if let turn = view.messages.first(where: { $0.id == identity.executionID }),
          turn.status != "queued", turn.status != "running"
        {
          guard turn.status == "completed", !turn.bubbles.isEmpty,
            let image = turn.attachments?.first,
            let cached = try await service.imageData(for: image), cached == photo.data
          else { throw NessaGatewayError.rejected("Image turn or cached bytes failed") }
          print("PASS: image reference, matching cached bytes and model response")
          print("MODEL_REPLY: " + turn.bubbles.joined(separator: " "))
          completed = true
          break
        }
        try await Task.sleep(for: .seconds(1))
      }
      guard completed else { throw NessaGatewayError.timeout }
      try await service.delete(id)
      await service.disconnect()
      print("PASS: disposable image-test chat cleaned up")
    } catch {
      if let id = createdID { try? await service.delete(id) }
      await service.disconnect()
      throw error
    }
  }

  private static func pattern() throws -> Data {
    guard
      let context = CGContext(
        data: nil, width: 256, height: 256, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { throw NessaGatewayError.invalidFrame }
    context.setFillColor(CGColor(red: 0, green: 0.25, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 256, height: 256))
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fillEllipse(in: CGRect(x: 30, y: 85, width: 100, height: 100))
    context.setFillColor(CGColor(red: 1, green: 1, blue: 0, alpha: 1))
    context.fill(CGRect(x: 150, y: 90, width: 80, height: 80))
    let bytes = NSMutableData()
    guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithData(
        bytes, UTType.png.identifier as CFString, 1, nil)
    else { throw NessaGatewayError.invalidFrame }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw NessaGatewayError.invalidFrame }
    return bytes as Data
  }
}
