import Foundation
import Testing

@testable import NessaFeatures

@Test func profileRegistryPersistsSelectionAndExactIdentityAcrossReopening() async throws {
  let root = profileTestRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let first = exampleProfiles()
  let store = PhoneProfileStore(root: root)
  try await store.save(first, replacing: nil)
  let secondProfile = exampleProfile()
  let second = PhoneProfiles(
    revision: UUID(), selected: secondProfile.id,
    profiles: first.profiles + [secondProfile])
  try await store.save(second, replacing: first)
  #expect(try await PhoneProfileStore(root: root).load() == second)
  let file = try profileMetadataFile(root)
  let bytes = try Data(contentsOf: file)
  #expect(!String(decoding: bytes, as: UTF8.self).contains(root.path))
  let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
  #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
  // A stale view must not erase the second selected profile.
  await #expect(throws: PhoneProfileStoreError.changed) {
    try await store.save(first, replacing: first)
  }
  #expect(try await store.load() == second)
}

@Test func profileWriteFailurePreservesPublicationAndBlocksPreparationEffects() async throws {
  for (mode, error) in [
    (
      FaultingProfileFiles.Mode.beforeWrite,
      PhoneProfileStoreError.write(.notPublished, .unavailable, reconciliation: nil)
    ),
    (.afterWrite, .write(.published, .unavailable, reconciliation: nil)),
    (.failedReadback, .write(.uncertain, .unavailable, reconciliation: .quota)),
    (.differentReadback, .write(.uncertain, .unavailable, reconciliation: nil)),
  ] {
    let root = profileTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let files = FaultingProfileFiles(root: root, mode: mode)
    let keychain = MemoryProfileKeychain()
    let preparation = PhoneProfilePreparation(
      profiles: PhoneProfileStore(files: files),
      credentials: PhoneProfileCredentials(keychain: keychain))
    let profile = exampleProfile()
    await #expect(throws: error) {
      try await preparation.prepare(profile, credential: "fixture", replacing: nil)
    }
    #expect(keychain.inserts == 0)
    if mode == .afterWrite || mode == .failedReadback {
      let saved = try await PhoneProfileStore(root: root).load()
      #expect(saved?.profiles.first == profile)
      // Resume uses a fresh successful disk publication before touching Keychain.
      let recovered = try await PhoneProfilePreparation(
        profiles: PhoneProfileStore(root: root),
        credentials: PhoneProfileCredentials(keychain: keychain)
      ).prepare(profile, credential: "fixture", replacing: saved)
      #expect(recovered.profiles.first?.id == profile.id)
      #expect(recovered.profiles.first?.phase == .prepared)
      #expect(keychain.inserts == 1)
    }
  }
}

@Test func profileCompareAndSaveKeepsActualLockThroughPublication() async throws {
  let root = profileTestRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let files = FaultingProfileFiles(root: root, mode: .heldWrite)
  let first = exampleProfiles()
  let saving = Task { try await PhoneProfileStore(files: files).save(first, replacing: nil) }
  let entered = await files.waitForEntry()
  #expect(entered)
  guard entered else {
    files.release.signal()
    try await saving.value
    return
  }
  await #expect(throws: PhoneProfileStoreError.storage(.unavailable)) {
    try await PhoneProfileStore(root: root).save(exampleProfiles(), replacing: nil)
  }
  files.release.signal()
  try await saving.value
  #expect(try await PhoneProfileStore(root: root).load() == first)
}

@Test func profileStoreRefusesCorruptionQuotaAndImpossibleRegistryTransitions() async throws {
  let root = profileTestRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let store = PhoneProfileStore(root: root)
  let first = exampleProfiles()
  try await store.save(first, replacing: nil)
  let file = try profileMetadataFile(root)
  try Data("broken".utf8).write(to: file)
  await #expect(throws: PhoneProfileStoreError.corrupt) { try await store.load() }
  try Data(count: 1025).write(to: file)
  await #expect(throws: PhoneProfileStoreError.storage(.quota)) {
    try await PhoneProfileStore(root: root, maximumBytes: 1024).load()
  }
  let invalid = PhoneProfiles(
    revision: UUID(), selected: first.selected, profiles: first.profiles + first.profiles)
  try JSONEncoder().encode(invalid).write(to: file)
  await #expect(throws: PhoneProfileStoreError.corrupt) { try await store.load() }
  await #expect(throws: PhoneProfileStoreError.invalid) {
    try await store.save(invalid, replacing: nil)
  }
  let prepared = exampleProfiles(first.profiles[0].changingPhase(to: .prepared))
  await #expect(throws: PhoneProfileStoreError.invalid) {
    try await store.save(prepared, replacing: nil)
  }
  // A future transition must keep prior identities and mint a different revision.
  let changed = PhoneProfiles(
    revision: first.revision, selected: first.selected,
    profiles: [first.profiles[0].changingPhase(to: .prepared)])
  await #expect(throws: PhoneProfileStoreError.invalid) {
    try await store.save(changed, replacing: first)
  }
}

@Test func profileStoreDoesNotTreatNormalizedEqualAccountBytesAsTheExpectedWrite() async throws {
  let root = profileTestRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let profile = exampleProfile()
  let original = PhoneProfile(
    id: profile.id, productAddress: profile.productAddress, instance: profile.instance,
    nativeAddress: profile.nativeAddress, identity: profileIdentity(Array(repeating: "é", count: 6))
  )
  let value = exampleProfiles(original)
  let store = PhoneProfileStore(root: root)
  try await store.save(value, replacing: nil)
  let foreign = PhoneProfile(
    id: original.id, productAddress: original.productAddress, instance: original.instance,
    nativeAddress: original.nativeAddress,
    identity: profileIdentity(Array(repeating: "e\u{301}", count: 6)))
  let expected = PhoneProfiles(
    revision: value.revision, selected: value.selected, profiles: [foreign])
  await #expect(throws: PhoneProfileStoreError.changed) {
    try await store.save(expected, replacing: expected)
  }
  #expect(try await store.load() == value)
}

@Test func profileReplacementCannotRemoveIdentityChangeSelectorsOrRegressPreparedState()
  async throws
{
  let root = profileTestRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let original = exampleProfiles()
  let store = PhoneProfileStore(root: root)
  try await store.save(original, replacing: nil)
  let prepared = PhoneProfiles(
    revision: UUID(), selected: original.selected,
    profiles: [original.profiles[0].changingPhase(to: .prepared)])
  try await store.save(prepared, replacing: original)
  let other = exampleProfile()
  let removed = PhoneProfiles(revision: UUID(), selected: other.id, profiles: [other])
  await #expect(throws: PhoneProfileStoreError.invalid) {
    try await store.save(removed, replacing: prepared)
  }
  let regressed = PhoneProfiles(
    revision: UUID(), selected: prepared.selected, profiles: original.profiles)
  await #expect(throws: PhoneProfileStoreError.invalid) {
    try await store.save(regressed, replacing: prepared)
  }
  let prior = prepared.profiles[0]
  let changed = PhoneProfile(
    id: prior.id, phase: .prepared, productAddress: prior.productAddress,
    instance: prior.instance, nativeAddress: "127.0.0.1:47651", identity: prior.identity)
  let foreign = PhoneProfiles(revision: UUID(), selected: changed.id, profiles: [changed])
  await #expect(throws: PhoneProfileStoreError.invalid) {
    try await store.save(foreign, replacing: prepared)
  }
  #expect(try await store.load() == prepared)
}
