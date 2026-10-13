import Foundation
import Testing

@testable import NessaFeatures

private func deletionIntent(
  scope: PhoneDeletionScope? = nil, request: UUID = UUID(),
  conversation: String = UUID().uuidString.lowercased()
) -> PhoneDeletionIntent {
  .init(
    scope: scope
      ?? .init(
        owner: profileIdentity(), productAddress: "ws://127.0.0.1:19743/session", instance: "phone",
        profileID: UUID()), requestID: request, conversationID: conversation)
}
@Test func deletionStoreColdRestartCASAndHistoricalFalseAcknowledgment() async throws {
  let root = profileTestRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let intent = deletionIntent()
  let store = PhoneDeletionIntentStore(root: root)
  try await store.save(intent)
  let cold = PhoneDeletionIntentStore(root: root)
  #expect(try await cold.load(scope: intent.scope) == [.init(intent: intent)])
  try await cold.save(intent)
  let conflict = deletionIntent(scope: intent.scope, request: intent.requestID)
  await #expect(throws: (any Error).self) { try await cold.save(conflict) }
  let ack = PhoneDeletionAcknowledgment(
    requestId: intent.requestID.uuidString.lowercased(), applied: false)
  try await cold.acknowledge(intent, value: ack)
  #expect(try await store.load(scope: intent.scope) == [.init(intent: intent, acknowledgment: ack)])
  await #expect(throws: (any Error).self) {
    try await store.acknowledge(
      intent, value: .init(requestId: intent.requestID.uuidString.lowercased(), applied: true))
  }
}
@Test func deletionStoreProtectedScopeIsolationAndCorruptionNeverFakeAbsence() async throws {
  let root = profileTestRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let intent = deletionIntent()
  let store = PhoneDeletionIntentStore(root: root)
  try await store.save(intent)
  let foreign = PhoneDeletionScope(
    owner: profileIdentity(["owner", "owner", "owner", "owner", "different-surface", "owner"]),
    productAddress: intent.scope.productAddress, instance: intent.scope.instance,
    profileID: intent.scope.profileID)
  #expect(try await store.load(scope: foreign).isEmpty)
  let file = try profileMetadataFile(root)
  let bytes = try Data(contentsOf: file)
  let text = try #require(String(data: bytes, encoding: .utf8))
  #expect(!text.contains("credentialToken"))
  #expect(!text.contains("checkpoint"))
  let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
  #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
  try Data("not-json".utf8).write(to: file)
  await #expect(throws: (any Error).self) { _ = try await store.load(scope: intent.scope) }
  // A valid document placed under the wrong scope key also refuses instead of disappearing.
  try JSONEncoder().encode([PhoneDeletionRecord(intent: deletionIntent(scope: foreign))]).write(
    to: file)
  await #expect(throws: (any Error).self) { _ = try await store.load(scope: intent.scope) }
}
@Test func deletionStoreBoundedRecordsAndQuotaPreservePriorFacts() async throws {
  let root = profileTestRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = PhoneDeletionIntentStore(root: root)
  let first = deletionIntent()
  for _ in 0..<64 { try await store.save(deletionIntent(scope: first.scope)) }
  await #expect(throws: (any Error).self) { try await store.save(first) }
  #expect(try await PhoneDeletionIntentStore(root: root).load(scope: first.scope).count == 64)
  let tinyRoot = profileTestRoot()
  defer { try? FileManager.default.removeItem(at: tinyRoot) }
  let tiny = PhoneDeletionIntentStore(root: tinyRoot, maximumBytes: 16)
  do {
    try await tiny.save(first)
    Issue.record("Expected quota failure")
  } catch let PhoneDeletionStoreFailure.write(visibility, underlying, _) {
    #expect(visibility == .notPublished)
    #expect(underlying is PrivatePhoneFileError)
  }
  #expect(try await PhoneDeletionIntentStore(root: tinyRoot).load(scope: first.scope).isEmpty)
}
@Test func deletionStoreVisibilityNeverMeansDurableWriteSuccess() async throws {
  for mode in [FaultingProfileFiles.Mode.beforeWrite, .afterWrite, .failedReadback] {
    let root = profileTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let intent = deletionIntent()
    let store = PhoneDeletionIntentStore(files: FaultingProfileFiles(root: root, mode: mode))
    do {
      try await store.save(intent)
      Issue.record("Expected durability failure")
    } catch let PhoneDeletionStoreFailure.write(visibility, underlying, reconciliation) {
      #expect(underlying is PrivatePhoneFileError)
      switch mode {
      case .beforeWrite: #expect(visibility == .notPublished)
      case .afterWrite: #expect(visibility == .published)
      default:
        #expect(visibility == .uncertain)
        #expect(reconciliation is PrivatePhoneFileError)
      }
    }
    #expect(
      try await PhoneDeletionIntentStore(root: root).load(scope: intent.scope).count
        == (mode == .beforeWrite ? 0 : 1))
  }
}
@Test func deletionStoreOfflineDisplaySelectorNeverBecomesRetryAuthority() async throws {
  let root = profileTestRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let cache = PhoneCacheScope(
    address: "ws://127.0.0.1:19743/session", credential: "private-token-never-serialize",
    instance: "phone")
  let profile = UUID()
  let a = PhoneDeletionScope(
    owner: profileIdentity(), productAddress: "ws://127.0.0.1:19743/session", instance: "phone",
    profileID: profile, displayCache: cache)
  let b = PhoneDeletionScope(
    owner: profileIdentity(["owner", "owner", "owner", "owner", "rotated-owner", "owner"]),
    productAddress: a.productAddress, instance: a.instance, profileID: profile, displayCache: cache)
  let first = deletionIntent(scope: a)
  let second = deletionIntent(scope: b)
  let store = PhoneDeletionIntentStore(root: root)
  try await store.save(first)
  try await store.save(second)
  try await store.acknowledge(
    first, value: .init(requestId: first.requestID.uuidString.lowercased(), applied: false))
  let cold = PhoneDeletionIntentStore(root: root)
  let display = try await cold.loadForDisplay(cache: cache, profileID: profile)
  #expect(display.count == 2)
  #expect(display.first?.acknowledgment?.applied == false)
  #expect(try await cold.load(scope: a).map(\.intent) == [first])
  #expect(try await cold.load(scope: b).map(\.intent) == [second])
  #expect(try await cold.loadForDisplay(cache: cache, profileID: UUID()).isEmpty)
  let changedCache = PhoneCacheScope(
    address: a.productAddress, credential: "changed-token", instance: a.instance)
  #expect(try await cold.loadForDisplay(cache: changedCache, profileID: profile).isEmpty)
  let file = try profileMetadataFile(root)
  #expect(
    !String(decoding: try Data(contentsOf: file), as: UTF8.self).contains(
      "private-token-never-serialize"))
  let badScope = PhoneDeletionScope(
    owner: a.owner, productAddress: a.productAddress, instance: a.instance, profileID: profile,
    displayCache: changedCache)
  try JSONEncoder().encode([PhoneDeletionRecord(intent: deletionIntent(scope: badScope))]).write(
    to: file)
  await #expect(throws: (any Error).self) {
    _ = try await cold.loadForDisplay(cache: cache, profileID: profile)
  }
  await #expect(throws: (any Error).self) { _ = try await cold.load(scope: a) }
}
