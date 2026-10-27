import CryptoKit
import Foundation
import NessaFeatures

/// Real phone use case → gateway upload → provider workspace → retained view.
enum FileVerification {
  @MainActor static func run(endpoint: String, credentialFile: String) async throws {
    let credential = try String(contentsOfFile: credentialFile, encoding: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    for usesOutbox in [false, true] {
      try await check(
        endpoint: endpoint, credential: credential,
        root: root.appendingPathComponent(usesOutbox ? "outbox" : "journal"), usesOutbox: usesOutbox
      )
    }
  }
  @MainActor private static func check(
    endpoint: String, credential: String, root: URL, usesOutbox: Bool
  ) async throws {
    let client = NessaGatewayClient(
      journal: PhoneCommandJournal(store: PhoneCommandStore(root: root)))
    let service = MessagingService(repository: client, directory: client)
    let phoneChat =
      usesOutbox
      ? NessaDependencies(
        mode: .live, repository: client,
        credentials: InMemoryCredentialStore(), preferences: InMemoryChatPreferences(),
        snapshots: PhoneSnapshotSession(store: InMemoryPhoneSnapshotStore()),
        phoneOutboxRoot: root.appendingPathComponent("sends")
      ).phoneChat : nil
    let model = MessagesViewModel(
      service: service, credentials: InMemoryCredentialStore(),
      preferences: InMemoryChatPreferences(), phoneChat: phoneChat)
    await model.connect(address: endpoint, credential: credential, instance: "phone-file-check")
    guard model.connected, let id = await model.create() else {
      throw NessaGatewayError.rejected(model.error ?? "Create failed")
    }
    do {
      for (name, mime, header) in [
        ("report.pdf", "application/pdf", "%PDF-1.7\n"),
        ("archive.zip", "application/zip", "PK\u{03}\u{04}"),
        ("notes.txt", "text/plain", "phone file sending\n"),
      ] {
        let data = Data((header + String(repeating: "0123456789abcdef", count: 4500)).utf8)
        let digest = "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let identity = MessageCommandIdentity()
        let correlation = "uploaded-file-" + identity.executionID.lowercased()
        guard
          await model.send(
            "fixtureCorrelation:" + correlation,
            attachments: [DraftAttachment(name: name, mimeType: mime, data: data)],
            to: id, identity: identity)
        else { throw NessaGatewayError.rejected(model.error ?? "File send failed") }
        var completed = false
        for _ in 0..<200 {
          let view = try await service.read(id)
          if let turn = view.messages.first(where: { $0.id == identity.executionID }),
            turn.status != "queued", turn.status != "running"
          {
            guard turn.status == "completed", turn.uploads?.count == 1,
              let file = turn.uploads?.first, file.digest == digest,
              file.mimeType == mime, file.size == data.count, file.name == name,
              turn.bubbles.joined().contains("file-" + digest)
            else {
              throw NessaGatewayError.rejected(
                "File check: status=\(turn.status), error=\(turn.error ?? "none"), refs=\(String(describing: turn.uploads)), reply=\(turn.bubbles)"
              )
            }
            completed = true
            break
          }
          try await Task.sleep(for: .milliseconds(50))
        }
        guard completed, try await service.pendingCommands().isEmpty else {
          throw NessaGatewayError.timeout
        }
        print(
          "PASS: phone \(usesOutbox ? "outbox" : "journal") \(name), \(data.count) bytes, verified provider SHA-256 and original history reference"
        )
      }
      try await service.delete(id)
      await service.disconnect()
    } catch {
      try? await service.delete(id)
      await service.disconnect()
      throw error
    }
  }
}
