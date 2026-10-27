import CryptoKit
import Foundation
import NessaFeatures

/// Real phone use case → gateway upload → provider workspace → retained view.
enum FileVerification {
  struct StressConfiguration: Decodable {
    let endpoint: String
    let credential: String
    let conversationID: String
    let prefix: String
  }
  struct SentFile: Encodable {
    let text: String
    let name: String
    let mimeType: String
    let digest: String
    let size: Int
    let executionID: String
    let usesOutbox: Bool
  }
  @MainActor static func stress(configurationFile: String) async throws {
    let configuration = try JSONDecoder().decode(
      StressConfiguration.self, from: Data(contentsOf: URL(fileURLWithPath: configurationFile)))
    let credential = configuration.credential
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    var files: [SentFile] = []
    for usesOutbox in [false, true] {
      files += try await check(
        endpoint: configuration.endpoint, credential: credential,
        root: root.appendingPathComponent(usesOutbox ? "outbox" : "journal"),
        usesOutbox: usesOutbox, stress: configuration)
    }
    let data = try JSONEncoder().encode(files)
    guard let json = String(data: data, encoding: .utf8) else {
      throw NessaGatewayError.rejected("Invalid stress result encoding")
    }
    print("PHONE_FILES_RESULT:" + json)
  }

  @MainActor static func run(endpoint: String, credentialFile: String) async throws {
    let credential = try String(contentsOfFile: credentialFile, encoding: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    for usesOutbox in [false, true] {
      _ = try await check(
        endpoint: endpoint, credential: credential,
        root: root.appendingPathComponent(usesOutbox ? "outbox" : "journal"), usesOutbox: usesOutbox
      )
    }
  }
  @MainActor private static func check(
    endpoint: String, credential: String, root: URL, usesOutbox: Bool,
    stress: StressConfiguration? = nil
  ) async throws -> [SentFile] {
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
    guard model.connected else {
      throw NessaGatewayError.rejected(model.error ?? "Connect failed")
    }
    let selectedID: String?
    if let stress { selectedID = stress.conversationID } else { selectedID = await model.create() }
    guard let id = selectedID else {
      throw NessaGatewayError.rejected(model.error ?? "Create failed")
    }
    var sent: [SentFile] = []
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
        let text = stress.map {
          $0.prefix + " uploaded input " + (usesOutbox ? "outbox " : "journal ") + name + " " + identity.executionID
        } ?? "fixtureCorrelation:" + correlation
        guard
          await model.send(
            text,
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
              stress != nil || turn.bubbles.joined().contains("file-" + digest)
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
        if stress != nil {
          // Retry through the same product path and identity, including its journal/outbox.
          guard await model.send(text,
            attachments: [DraftAttachment(name: name, mimeType: mime, data: data)],
            to: id, identity: identity),
            try await service.read(id).messages.filter({ $0.id == identity.executionID }).count == 1,
            try await service.pendingCommands().isEmpty
          else { throw NessaGatewayError.rejected(model.error ?? "File retry changed identity") }
          sent.append(SentFile(text: text, name: name, mimeType: mime, digest: digest,
            size: data.count, executionID: identity.executionID, usesOutbox: usesOutbox))
        } else {
          print(
            "PASS: phone \(usesOutbox ? "outbox" : "journal") \(name), \(data.count) bytes, verified provider SHA-256 and original history reference"
          )
        }
      }
      if stress == nil { try await service.delete(id) }
      await service.disconnect()
      return sent
    } catch {
      if stress == nil { try? await service.delete(id) }
      await service.disconnect()
      throw error
    }
  }
}
