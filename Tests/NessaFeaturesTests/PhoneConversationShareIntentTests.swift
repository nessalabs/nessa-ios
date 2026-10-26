import Foundation
import Testing

@testable import NessaFeatures

private func sharingIntent(
  profile: UUID = UUID(), request: UUID = UUID(),
  conversation: String = UUID().uuidString.lowercased()
) -> PhoneConversationShareIntent {
  let owner = coordinatorOwner(phase: .active)
  let device = GatewayPairingStatus(
    invitationID: owner.invitationID, consentID: owner.consentID,
    generation: owner.generation, consentClass: owner.consentClass, grant: owner.grant,
    createdAtMs: owner.createdAtMs, expiresAtMs: owner.expiresAtMs, phase: .active,
    claimedDeviceKey: owner.claimedDeviceKey, credentialID: "native-credential",
    receiver: .init(id: "native-receiver", accessEpoch: 99), terminal: nil, cleanupPending: false)
  return .init(
    requestID: request, conversationID: conversation, profileID: profile,
    owner: profileIdentity(), instance: "phone", device: device)
}

@Test func sharingIntentPhysicalRestartAndExactReplay() async throws {
  let root = profileTestRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let intent = sharingIntent()
  let store = PhoneConversationShareIntentStore(root: root)
  try await store.save(intent)
  let reopened = PhoneConversationShareIntentStore(root: root)
  #expect(try await reopened.load(profileID: intent.profileID) == [.init(intent: intent)])
  try await reopened.save(intent)
  #expect(try await reopened.load(profileID: intent.profileID).count == 1)
  let acknowledgment = try JSONDecoder().decode(
    PhoneConversationShareAcknowledgment.self,
    from: Data(
      "{\"requestId\":\"\(intent.requestID.uuidString.lowercased())\",\"applied\":false}".utf8))
  try await reopened.acknowledge(intent, value: acknowledgment)
  #expect(
    try await store.load(profileID: intent.profileID) == [
      .init(intent: intent, acknowledgment: acknowledgment)
    ])
  let replacement = sharingIntent(
    profile: intent.profileID, request: intent.requestID,
    conversation: UUID().uuidString.lowercased())
  await #expect(throws: (any Error).self) { try await store.save(replacement) }
  #expect(try await store.load(profileID: intent.profileID).first?.intent == intent)
}

@Test func sharingIntentCapacityDoesNotLoseEarlierRequests() async throws {
  let root = profileTestRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = PhoneConversationShareIntentStore(root: root)
  let profile = UUID()
  for _ in 0..<64 { try await store.save(sharingIntent(profile: profile)) }
  await #expect(throws: (any Error).self) {
    try await store.save(
      sharingIntent(profile: profile, conversation: UUID().uuidString.lowercased()))
  }
  #expect(
    try await PhoneConversationShareIntentStore(root: root).load(profileID: profile).count == 64)
}

@Test func sharingIntentWriteFailuresPreserveVisibilityAndUnderlyingEvidence() async throws {
  for mode in [FaultingProfileFiles.Mode.beforeWrite, .afterWrite, .failedReadback] {
    let root = profileTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let intent = sharingIntent()
    let store = PhoneConversationShareIntentStore(
      files: FaultingProfileFiles(root: root, mode: mode))
    do {
      try await store.save(intent)
      Issue.record("Durability failure must remain a failure")
    } catch let PhoneConversationShareStoreFailure.write(visibility, underlying, reconciliation) {
      #expect(underlying is PrivatePhoneFileError)
      switch mode {
      case .beforeWrite: #expect(visibility == .notPublished)
      case .afterWrite: #expect(visibility == .published)
      default:
        #expect(visibility == .uncertain)
        #expect(reconciliation is PrivatePhoneFileError)
      }
    }
    let cold = try await PhoneConversationShareIntentStore(root: root).load(
      profileID: intent.profileID)
    #expect(cold.count == (mode == .beforeWrite ? 0 : 1))
  }
}
@Test func sharingIntentTwoStoreOwnersMergeUnderPhysicalLock() async throws {
  let root = profileTestRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  let first = PhoneConversationShareIntentStore(root: root)
  let second = PhoneConversationShareIntentStore(root: root)
  let profile = UUID()
  let a = sharingIntent(profile: profile)
  let b = sharingIntent(profile: profile)
  async let saveA: Void? = try? first.save(a)
  async let saveB: Void? = try? second.save(b)
  _ = await (saveA, saveB)
  // The shared file port refuses overlapping locks; retry the same immutable intents.
  try await first.save(a)
  try await second.save(b)
  let cold = try await PhoneConversationShareIntentStore(root: root).load(profileID: profile)
  #expect(Set(cold.map { $0.intent.requestID }) == Set([a.requestID, b.requestID]))
}
@Test func sharingIntentQuotaRefusesWithoutPretendingPublication() async throws {
  let root = profileTestRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let intent = sharingIntent()
  let small = PhoneConversationShareIntentStore(root: root, maximumBytes: 16)
  do {
    try await small.save(intent)
    Issue.record("Expected quota failure")
  } catch let PhoneConversationShareStoreFailure.write(publication, underlying, _) {
    #expect(publication == .notPublished)
    #expect(underlying is PrivatePhoneFileError)
  }
  #expect(
    try await PhoneConversationShareIntentStore(root: root).load(profileID: intent.profileID)
      .isEmpty)
}
@Test func sharingIntentUsesPublishedUUIDAndUTF8RequestBounds() throws {
  let conversation = UUID().uuidString.lowercased()
  func frame(_ conversation: String, _ request: String) throws -> Data {
    try JSONSerialization.data(withJSONObject: [
      "conversationId": conversation, "requestId": request,
      "credentialId": "native-credential", "capabilities": ["read"],
    ])
  }
  try validateGatewayWire(
    frame(conversation, String(repeating: "é", count: 128)), named: "ConversationShareParams")
  #expect(throws: (any Error).self) {
    try validateGatewayWire(
      frame(conversation, String(repeating: "é", count: 129)), named: "ConversationShareParams")
  }
  #expect(throws: (any Error).self) {
    try validateGatewayWire(
      frame(conversation.uppercased(), "request"), named: "ConversationShareParams")
  }
  #expect(throws: (any Error).self) {
    try validateGatewayWire(
      frame("x" + conversation.dropFirst(), "request"), named: "ConversationShareParams")
  }
}
@Test func sharingIntentCASRejectsByteDistinctFrozenInstance() async throws {
  let root = profileTestRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let base = sharingIntent()
  let a = PhoneConversationShareIntent(
    requestID: base.requestID, conversationID: base.conversationID,
    profileID: base.profileID, owner: base.owner, instance: "é", device: base.device)
  let b = PhoneConversationShareIntent(
    requestID: base.requestID, conversationID: base.conversationID,
    profileID: base.profileID, owner: base.owner, instance: "e\u{301}", device: base.device)
  let store = PhoneConversationShareIntentStore(root: root)
  try await store.save(a)
  await #expect(throws: (any Error).self) { try await store.save(b) }
  let saved = try #require(await store.load(profileID: base.profileID).first?.intent)
  #expect(saved.instance.utf8.elementsEqual(a.instance.utf8))
}
