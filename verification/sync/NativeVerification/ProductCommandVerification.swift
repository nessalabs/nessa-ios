import Foundation
import NessaFeatures

private enum ProductCommandFailure: Error { case assertion(String) }
private actor CorruptCommands: CommandJournalStoring {
  func load(_ scope: PhoneCacheScope) throws -> PhoneCommands? {
    throw PhoneCommandStoreError.corrupt
  }
  func save(_ commands: PhoneCommands, scope: PhoneCacheScope, replacing expected: PhoneCommands?)
    throws
  {
    throw PhoneCommandStoreError.corrupt
  }
}

enum ProductCommandVerification {
  @MainActor static func fixtures(_ endpoint: String) async throws {
    try await refusals(endpoint)
    for (operation, absentReceipt) in [("create", false), ("submit", false), ("submit", true)] {
      let mode = "journal-product-lost-" + operation + (absentReceipt ? "-unknown" : "")
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: root) }
      let firstClient = NessaGatewayClient(
        journal: PhoneCommandJournal(store: PhoneCommandStore(root: root)))
      let firstService = MessagingService(repository: firstClient, directory: firstClient)
      let first = model(firstService)
      await first.connect(address: endpoint, credential: "fixture-only", instance: mode)
      guard first.connected else {
        throw ProductCommandFailure.assertion("First app connection failed")
      }
      var id: String?
      let identity = MessageCommandIdentity()
      if operation == "create" {
        guard await first.create() == nil else {
          throw ProductCommandFailure.assertion("Lost create ACK returned success")
        }
      } else {
        guard let created = await first.create() else {
          throw ProductCommandFailure.assertion("Setup create failed")
        }
        id = created
        guard await first.send("Frozen synthetic message", to: created, identity: identity) == false
        else {
          throw ProductCommandFailure.assertion("Lost send ACK returned success")
        }
      }
      await firstService.disconnect()

      // Recreate the transport, journal and presentation owner, as after app termination.
      let replacementClient = NessaGatewayClient(
        journal: PhoneCommandJournal(store: PhoneCommandStore(root: root)))
      let replacementService = MessagingService(
        repository: replacementClient, directory: replacementClient)
      let replacement = model(replacementService)
      await replacement.connect(address: endpoint, credential: "fixture-only", instance: mode)
      guard replacement.connected, replacement.pendingCommands.count == 1,
        let intent = replacement.pendingCommands.first
      else {
        throw ProductCommandFailure.assertion(
          "App relaunch did not load exactly one pending intent")
      }
      if operation == "submit" {
        guard intent.requestID == identity.requestID, intent.conversationID == id,
          !replacement.canSubmit(in: intent.conversationID)
        else {
          throw ProductCommandFailure.assertion("Relaunch replaced or failed to block pending send")
        }
      }
      _ = await replacement.recoverCommand(intent.requestID, retry: false)
      if absentReceipt {
        guard replacement.pendingCommands == [intent], replacement.acknowledgedCommands.isEmpty
        else {
          throw ProductCommandFailure.assertion("Absent receipt invented confirmation")
        }
        _ = await replacement.recoverCommand(intent.requestID, retry: true)
      }
      guard replacement.pendingCommands.isEmpty,
        try await replacementService.pendingCommands().isEmpty,
        replacement.acknowledgedCommands.contains(intent.requestID)
      else {
        throw ProductCommandFailure.assertion(
          "App recovery did not durably confirm original intent")
      }
      let view = try await replacementService.read(intent.conversationID)
      guard view.runtime?.agent == "creates-1",
        view.messages.count == (operation == "submit" ? 1 : 0)
      else {
        throw ProductCommandFailure.assertion("App recovery duplicated an effect")
      }
      await replacementService.disconnect()
      print(
        "PASS: product lost \(operation) ACK, cold journal hydration and \(absentReceipt ? "explicit exact retry" : "receipt-only check") preserve one effect"
      )
    }
    let client = NessaGatewayClient(journal: PhoneCommandJournal(store: CorruptCommands()))
    let service = MessagingService(repository: client, directory: client)
    let presentation = model(service)
    await presentation.connect(
      address: endpoint, credential: "fixture-only", instance: "journal-product-corrupt")
    guard presentation.connected, presentation.pendingLoadError != nil,
      await presentation.create() == nil,
      await presentation.send("Must not dispatch", to: "00000000-0000-4000-8000-000000000001")
        == false
    else {
      throw ProductCommandFailure.assertion("Corrupt journal did not fail product commands closed")
    }
    _ = try await service.list()
    do {
      _ = try await service.create(agent: nil)
      throw ProductCommandFailure.assertion("Repository bypassed failed journal binding")
    } catch PhoneCommandStoreError.corrupt {}
    await service.disconnect()
    print(
      "PASS: corrupt journal preserves authenticated reads and blocks product/repository writes")
  }
  @MainActor private static func refusals(_ endpoint: String) async throws {
    for operation in ["create", "submit"] {
      let mode = "journal-product-refusal-" + operation
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
      defer { try? FileManager.default.removeItem(at: root) }
      let client = NessaGatewayClient(
        journal: PhoneCommandJournal(store: PhoneCommandStore(root: root)))
      let service = MessagingService(repository: client, directory: client)
      let presentation = model(service)
      await presentation.connect(address: endpoint, credential: "fixture-only", instance: mode)
      if operation == "create" {
        guard await presentation.create() == nil, presentation.pendingCreations.isEmpty,
          await presentation.create() != nil
        else {
          throw ProductCommandFailure.assertion(
            "First creation refusal blocked a corrected new intent")
        }
      } else {
        guard let id = await presentation.create() else {
          throw ProductCommandFailure.assertion("Refusal setup failed")
        }
        let photo = DraftAttachment(
          name: "fixture.png", mimeType: "image/png", data: Data([1, 2, 3]))
        guard await presentation.send("Refused photo", attachments: [photo], to: id) == false,
          presentation.acknowledgedCommands.isEmpty, presentation.pendingCommands.isEmpty,
          await presentation.send("Corrected text", to: id)
        else {
          throw ProductCommandFailure.assertion(
            "First photo refusal confirmed or blocked the corrected draft")
        }
      }
      await service.disconnect()
      let replacement = NessaGatewayClient(
        journal: PhoneCommandJournal(store: PhoneCommandStore(root: root)))
      try await replacement.connect(address: endpoint, credential: "fixture-only", instance: mode)
      guard try await replacement.pendingCommands().isEmpty else {
        throw ProductCommandFailure.assertion("Rejected intent reappeared after disk recreation")
      }
      await replacement.disconnect()
      print(
        "PASS: typed first \(operation) refusal releases reservation across restart and allows a fresh corrected intent"
      )
    }
    let mode = "journal-product-lost-create-later-refusal"
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let client = NessaGatewayClient(
      journal: PhoneCommandJournal(store: PhoneCommandStore(root: root)))
    let service = MessagingService(repository: client, directory: client)
    let presentation = model(service)
    await presentation.connect(address: endpoint, credential: "fixture-only", instance: mode)
    guard await presentation.create() == nil else {
      throw ProductCommandFailure.assertion("Expected lost create ACK")
    }
    await service.disconnect()
    let replacementClient = NessaGatewayClient(
      journal: PhoneCommandJournal(store: PhoneCommandStore(root: root)))
    let replacementService = MessagingService(
      repository: replacementClient, directory: replacementClient)
    let replacement = model(replacementService)
    await replacement.connect(address: endpoint, credential: "fixture-only", instance: mode)
    guard let original = replacement.pendingCommands.first else {
      throw ProductCommandFailure.assertion("Missing uncertain creation")
    }
    _ = await replacement.recoverCommand(original.requestID, retry: true)
    guard replacement.pendingCommands == [original], replacement.acknowledgedCommands.isEmpty,
      await replacement.create() == nil
    else {
      throw ProductCommandFailure.assertion("Later refusal erased earlier uncertain acceptance")
    }
    await replacementService.disconnect()
    print(
      "PASS: cold-recreated uncertain command survives a later typed refusal and absent receipt")
  }
  @MainActor private static func model(_ service: MessagingService) -> MessagesViewModel {
    MessagesViewModel(
      service: service, credentials: InMemoryCredentialStore(),
      preferences: InMemoryChatPreferences())
  }
}
