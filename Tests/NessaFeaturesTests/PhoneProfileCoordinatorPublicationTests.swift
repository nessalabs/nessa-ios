import Foundation
import Testing

@testable import NessaFeatures

private final class CoordinatorPublicationFiles: PrivatePhoneFileAccess, @unchecked Sendable {
  enum Target { case request, owner }
  let files: PrivatePhoneFiles
  let target: Target
  let afterWrite: Bool
  init(root: URL, target: Target, afterWrite: Bool) {
    files = PrivatePhoneFiles(root: root, maximumBytes: 1024 * 1024)
    self.target = target
    self.afterWrite = afterWrite
  }
  func read(_ key: String) throws -> Data? { try files.read(key) }
  func write(_ data: Data, key: String) throws {
    let registry = try JSONDecoder().decode(PhoneProfiles.self, from: data)
    let profile = registry.profiles.first { $0.id == registry.selected }!
    let fail = target == .request ? profile.creationAttempt != nil : profile.pairingStatus != nil
    if !fail || afterWrite { try files.write(data, key: key) }
    if fail { throw PrivatePhoneFileError.unavailable }
  }
  func withLock<Value>(_ key: String, body: () throws -> Value) throws -> Value {
    try files.withLock(key, body: body)
  }
}

@Test func coordinatorRealCASReadbackDoesNotTurnFailedDurabilityIntoEnrollment() async throws {
  for target: CoordinatorPublicationFiles.Target in [.request, .owner] {
    for afterWrite in [false, true] {
      let root = profileTestRoot()
      defer { try? FileManager.default.removeItem(at: root) }
      let harness = CoordinatorHarness()
      let store = PhoneProfileStore(root: root)
      let preparing = exampleProfiles(harness.profile.changingPhase(to: .preparing))
      try await store.save(preparing, replacing: nil)
      let prepared = exampleProfiles(harness.profile)
      try await store.save(prepared, replacing: preparing)
      let faulting = PhoneProfileStore(
        files: CoordinatorPublicationFiles(root: root, target: target, afterWrite: afterWrite))
      let coordinator = PhoneProfileCoordinator(
        profiles: faulting, credentials: harness.credentials,
        locations: CoordinatorLocations(), identity: harness.gateway, pairing: harness.gateway,
        factory: harness.factory, withdrawal: harness.withdrawal)
      _ = try await coordinator.restore()
      do {
        _ = try await coordinator.startPairing(on: harness.lease)
        Issue.record("Failed durability advanced")
      } catch let failure as PhoneProfileCoordinationFailure {
        #expect(
          failure.underlying as? PhoneProfileStoreError
            == .write(
              afterWrite ? .published : .notPublished,
              .unavailable, reconciliation: nil))
        #expect((failure.owner != nil) == (target == .owner))
      }
      #expect(await harness.gateway.creates == (target == .request ? 0 : 1))
      #expect(await harness.native.enrolls == 0)
      try await coordinator.close()
      let visible = try #require(try await store.load())
      if target == .owner || afterWrite { #expect(visible.profiles[0].creationAttempt != nil) }
      if afterWrite { #expect((visible.profiles[0].pairingStatus != nil) == (target == .owner)) }
      let fresh = CoordinatorNative()
      let reopened = PhoneProfileCoordinator(
        profiles: store, credentials: harness.credentials,
        locations: CoordinatorLocations(), identity: harness.gateway, pairing: harness.gateway,
        factory: CoordinatorFactory(fresh), withdrawal: harness.withdrawal)
      _ = try await reopened.restore()
      if target == .owner || afterWrite {
        do {
          _ = try await reopened.startPairing(on: harness.lease)
          Issue.record("Restart duplicated ambiguous invitation")
        } catch let failure as PhoneProfileCoordinationFailure {
          #expect(
            failure.underlying as? PhoneProfileCoordinationRefusal == .knownInvitationNeedsRecovery)
        }
      }
      #expect(await fresh.enrolls == 0)
      #expect(await harness.gateway.creates == (target == .request ? 0 : 1))
      try await reopened.close()
    }
  }
}
