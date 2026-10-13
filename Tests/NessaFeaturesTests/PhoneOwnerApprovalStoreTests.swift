import Foundation
import Testing

@testable import NessaFeatures

private func storedApproval(owner: String = "owner", prepared: Bool = true)
  -> PhoneOwnerApprovalRecord
{
  let identity = GatewaySessionSnapshot.Identity(
    gatewayID: "gateway", principalID: owner, organizationID: "organization",
    membershipID: "membership", credentialID: "bootstrap-id", audienceID: "gateway")
  let resource = GatewaySessionSnapshot.Resource(organizationID: "organization", id: "gateway")
  let reservation = PhoneOwnerApprovalReservation(
    profileID: UUID(), requestID: UUID(),
    context: .init(
      bootstrap: identity, productAddress: "wss://gateway.example/session", instance: "phone",
      nativeAddress: "127.0.0.1:19744", gatewayPin: Data(repeating: 4, count: 44),
      consentClass: "gateway-owner-conversation-read-write",
      grants: ["conversation.read", "conversation.write", "server.read"].map {
        .init(action: $0, resource: resource)
      }))
  return .init(
    reservation: reservation,
    preparation: prepared
      ? .init(
        reservation: reservation, deviceKey: Data(repeating: 5, count: 32),
        signature: Data(repeating: 6, count: 64), digest: Data(repeating: 7, count: 32)) : nil)
}

@Test func ownerApprovalPrivateStoreColdRoundtripKeepsOriginalFacts() async throws {
  let root = profileTestRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = PhoneOwnerApprovalStore(root: root)
  #expect(try await store.load().isEmpty)
  let original = storedApproval(prepared: false)
  try await store.publish([original], replacing: [])
  let prepared = PhoneOwnerApprovalRecord(
    reservation: original.reservation,
    preparation: .init(
      reservation: original.reservation, deviceKey: Data(repeating: 8, count: 32),
      signature: Data(repeating: 9, count: 64), digest: Data(repeating: 10, count: 32)))
  try await store.publish([prepared], replacing: [original])
  let cold = PhoneOwnerApprovalStore(root: root)
  #expect(try await cold.load() == [prepared])
  let properties = try FileManager.default.attributesOfItem(atPath: profileMetadataFile(root).path)
  #expect((properties[.posixPermissions] as? NSNumber)?.intValue == 0o600)
}

@Test func ownerApprovalPrivateStoreKeepsUncertainWriteEvidence() async throws {
  for (mode, visibility) in [
    (FaultingProfileFiles.Mode.beforeWrite, PhoneProfilePublication.notPublished),
    (.afterWrite, .published), (.failedReadback, .uncertain), (.differentReadback, .uncertain),
  ] {
    let root = profileTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let store = PhoneOwnerApprovalStore(files: FaultingProfileFiles(root: root, mode: mode))
    let original = storedApproval()
    do {
      try await store.publish([original], replacing: [])
      Issue.record("Failed durability must not return successful publication")
    } catch let error as PhoneOwnerApprovalWriteFailure {
      #expect(error.visibility == visibility)
      guard case PrivatePhoneFileError.unavailable = error.underlying else {
        Issue.record("Original physical failure was replaced")
        continue
      }
      #expect((error.reconciliation != nil) == (mode == .failedReadback))
    }
    if mode == .beforeWrite {
      #expect(try await PhoneOwnerApprovalStore(root: root).load().isEmpty)
    } else if mode != .differentReadback {
      #expect(try await PhoneOwnerApprovalStore(root: root).load() == [original])
    }
  }
}

@Test func ownerApprovalPrivateStoreEqualVisibleRetryStillPublishes() async throws {
  let root = profileTestRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let files = FaultingProfileFiles(root: root, mode: .afterWrite)
  let store = PhoneOwnerApprovalStore(files: files)
  let original = storedApproval()
  do { try await store.publish([original], replacing: []) } catch let error
    as PhoneOwnerApprovalWriteFailure
  { #expect(error.visibility == .published) }
  #expect(try await PhoneOwnerApprovalStore(root: root).load() == [original])
  do {
    try await store.publish([original], replacing: [original])
    Issue.record("Equal visible bytes cannot skip physical durable publication")
  } catch let error as PhoneOwnerApprovalWriteFailure { #expect(error.visibility == .published) }
}

@Test func ownerApprovalPrivateStoreConcurrentCASPreservesWinner() async throws {
  enum Attempt: Sendable {
    case saved(PhoneOwnerApprovalRecord)
    case changed, busy
    case other(any Error)
  }
  let root = profileTestRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let first = PhoneOwnerApprovalStore(root: root)
  let second = PhoneOwnerApprovalStore(root: root)
  let records = [storedApproval(owner: "a"), storedApproval(owner: "b")]
  let outcomes = await withTaskGroup(of: Attempt.self, returning: [Attempt].self) { group in
    for (store, record) in zip([first, second], records) {
      group.addTask {
        do {
          try await store.publish([record], replacing: [])
          return .saved(record)
        } catch PhoneOwnerApprovalRefusal.changed { return .changed } catch PrivatePhoneFileError
          .unavailable
        { return .busy } catch { return .other(error) }
      }
    }
    var result: [Attempt] = []
    for await value in group { result.append(value) }
    return result
  }
  let winners = outcomes.compactMap {
    if case .saved(let record) = $0 { return record }
    return nil
  }
  #expect(winners.count == 1)
  for outcome in outcomes { if case .other(let error) = outcome { Issue.record(error) } }
  let cold = PhoneOwnerApprovalStore(root: root)
  #expect(try await cold.load() == winners)
  await #expect(throws: PhoneOwnerApprovalRefusal.changed) {
    try await second.publish([records[1]], replacing: [])
  }
  #expect(try await cold.load() == winners)
}

@Test func ownerApprovalPrivateStoreRefusesChangedUnicodeBytesAndCorruptHistory() async throws {
  let root = profileTestRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = PhoneOwnerApprovalStore(root: root)
  let original = storedApproval(owner: "caf\u{00e9}")
  try await store.publish([original], replacing: [])
  let before = try Data(contentsOf: profileMetadataFile(root))
  let c = original.reservation.context
  let identity = GatewaySessionSnapshot.Identity(
    gatewayID: c.bootstrap.gatewayID, principalID: "cafe\u{0301}",
    organizationID: c.bootstrap.organizationID, membershipID: c.bootstrap.membershipID,
    credentialID: c.bootstrap.credentialID, audienceID: c.bootstrap.audienceID)
  let changed = PhoneOwnerApprovalRecord(
    reservation: .init(
      profileID: original.reservation.profileID, requestID: original.reservation.requestID,
      context: .init(
        bootstrap: identity, productAddress: c.productAddress, instance: c.instance,
        nativeAddress: c.nativeAddress, gatewayPin: c.gatewayPin, consentClass: c.consentClass,
        grants: c.grants)))
  await #expect(throws: PhoneOwnerApprovalRefusal.changed) {
    try await store.publish([original], replacing: [changed])
  }
  #expect(try Data(contentsOf: profileMetadataFile(root)) == before)
  try Data("invalid journal".utf8).write(to: profileMetadataFile(root))
  await #expect(throws: DecodingError.self) { try await store.load() }
  await #expect(throws: PhoneOwnerApprovalRefusal.changed) {
    try await store.publish([original], replacing: [])
  }
  #expect(try Data(contentsOf: profileMetadataFile(root)) == Data("invalid journal".utf8))
}

@Test func ownerApprovalPrivateStoreQuotaAndSymlinkRefuseWithoutReplacement() async throws {
  let root = profileTestRoot()
  let alias = profileTestRoot()
  defer {
    try? FileManager.default.removeItem(at: alias)
    try? FileManager.default.removeItem(at: root)
  }
  let original = storedApproval()
  try await PhoneOwnerApprovalStore(root: root).publish([original], replacing: [])
  let before = try Data(contentsOf: profileMetadataFile(root))
  let small = PhoneOwnerApprovalStore(root: root, maximumBytes: 1)
  await #expect(throws: PrivatePhoneFileError.self) { try await small.load() }
  await #expect(throws: PrivatePhoneFileError.self) {
    try await small.publish([original], replacing: [original])
  }
  try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root)
  let linked = PhoneOwnerApprovalStore(root: alias)
  await #expect(throws: PrivatePhoneFileError.self) { try await linked.load() }
  await #expect(throws: PrivatePhoneFileError.self) {
    try await linked.publish([original], replacing: [original])
  }
  #expect(try Data(contentsOf: profileMetadataFile(root)) == before)
}
