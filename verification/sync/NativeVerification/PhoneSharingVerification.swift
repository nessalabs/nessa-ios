import Foundation
import NessaFeatures

private struct VerificationProfileCredential: PhoneProfileCredentialStoring {
  let reference: String
  let value: String
  func load(reference: String) throws -> String {
    guard self.reference.utf8.elementsEqual(reference.utf8) else {
      throw PhoneProfileCredentialError.missing
    }
    return value
  }
  func insertOrVerify(_ credential: String, reference: String) throws {
    guard self.reference.utf8.elementsEqual(reference.utf8),
      value.utf8.elementsEqual(credential.utf8)
    else { throw PhoneProfileCredentialError.conflict }
  }
}

/// Uses the production owners for an explicitly selected isolated test device/chat.
/// Close the app's physical native owner before opening this same private root.
enum PhoneSharingVerification {
  private enum Failure: Error { case target, changed, unavailable }
  static func run(_ arguments: [String]) async throws {
    let root = URL(fileURLWithPath: arguments[0], isDirectory: true)
    let profiles = PhoneProfileStore(root: root)
    guard let registry = try await profiles.load(),
      let original = registry.profiles.first(where: { $0.id == registry.selected }),
      original.productAddress == "ws://127.0.0.1:19743/session",
      original.nativeAddress == "127.0.0.1:19744", UUID(uuidString: arguments[2]) != nil
    else { throw Failure.target }
    let key = original.pairingStatus?.claimedDeviceKey?.map { String(format: "%02x", $0) }.joined()
    guard key == arguments[3] else { throw Failure.target }
    let credential = try String(contentsOfFile: arguments[1], encoding: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let client = NessaGatewayClient()
    let lease = try await client.connectWithLease(
      address: original.productAddress, credential: credential, instance: original.instance)
    let source = try await client.authenticatedSession(for: lease)
    guard source.snapshot.identity == original.identity else {
      await client.retire(lease)
      throw Failure.changed
    }
    let credentials = VerificationProfileCredential(
      reference: original.credentialReference, value: credential)
    let locations = PhoneNativeLocations(root: root)
    let snapshots = PhoneSnapshotSession(store: InMemoryPhoneSnapshotStore())
    let sync = PhoneSyncRuntime(
      profiles: profiles, credentials: credentials,
      factory: {
        PhoneProfileCoordinator(
          profiles: profiles, credentials: credentials, locations: locations,
          identity: client, pairing: client, factory: NativeRetainedSessionFactory(),
          withdrawal: snapshots)
      })
    do {
      guard let restored = try await sync.restore() else { throw Failure.unavailable }
      let sharing = PhoneConversationSharing(
        product: client, sync: sync, store: PhoneConversationShareIntentStore(root: root))
      let result = try await sharing.perform(
        .share(arguments[2]), context: .init(connection: nil, lease: lease, snapshot: restored)
      ) {
        guard try await client.authenticatedSession(for: lease) == source,
          let current = try await profiles.load(), current.selected == original.id,
          current.profiles.first(where: { $0.id == original.id })?.sameSetup(as: original) == true
        else { throw Failure.changed }
      }
      let display = try await sync.display(
        on: lease, conversations: [arguments[2]], revision: UUID())
      let transcript = display.transcripts[arguments[2]]
      let state: String
      let readable: Bool
      switch transcript {
      case .available(let value):
        state = value.value.state.rawValue
        if case .available = value.value.view { readable = true } else { readable = false }
      case .failed(let failure):
        state = String(reflecting: type(of: failure))
        readable = false
      case .none:
        state = "missing"
        readable = false
      }
      let report: [String: Any] = [
        "conversation": arguments[2], "deviceKey": arguments[3],
        "request": result.intent?.requestID.uuidString.lowercased() ?? "existing-grant",
        "acknowledged": result.acknowledgment != nil,
        "applied": result.acknowledgment.map { $0.applied as Any } ?? NSNull(),
        "currentGrant": result.shares?.contains {
          $0.credentialId == original.pairingStatus?.credentialID
        } ?? false,
        "nativeCommandReady": display.commandReady(on: lease),
        "nativeTranscript": state, "readable": readable,
        "nativeCatalogue": display.catalogue.list.conversations.map(\.id),
      ]
      FileHandle.standardOutput.write(
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]))
      FileHandle.standardOutput.write(Data("\n".utf8))
      try await sync.close()
      await client.retire(lease)
      guard readable, display.commandReady(on: lease) else { throw Failure.unavailable }
    } catch {
      try? await sync.close()
      await client.retire(lease)
      throw error
    }
  }
}
