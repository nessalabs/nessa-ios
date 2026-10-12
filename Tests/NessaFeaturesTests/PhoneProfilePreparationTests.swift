import Foundation
import Testing

@testable import NessaFeatures

@Test func profilePreparationRecoversTheSameRecordAfterCredentialAndFinalWriteInterruptions()
  async throws
{
  let root = profileTestRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let profile = exampleProfile()
  let store = PhoneProfileStore(root: root)
  let preparing = exampleProfiles(profile)
  try await store.save(preparing, replacing: nil)
  // These are the two crash windows: record only, or record and immutable item but no prepared save.
  for existing in [false, true] {
    let keychain = MemoryProfileKeychain(
      records: existing ? [profile.credentialReference: Data("fixture".utf8)] : [:])
    let current = try await store.load()
    let result = try await PhoneProfilePreparation(
      profiles: store,
      credentials: PhoneProfileCredentials(keychain: keychain)
    ).prepare(profile, credential: "fixture", replacing: current)
    #expect(result.selected == profile.id && result.profiles[0].id == profile.id)
    #expect(result.profiles[0].credentialReference == profile.credentialReference)
    #expect(result.profiles[0].phase == .prepared)
    #expect(keychain.inserts == (existing ? 0 : 1))
    #expect(try await PhoneProfileStore(root: root).load() == result)
  }
}

@Test func profilePreparationCannotInsertCredentialAfterStaleMetadataOrChangeAnExistingSetup()
  async throws
{
  let root = profileTestRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let profile = exampleProfile()
  let current = exampleProfiles(profile)
  let store = PhoneProfileStore(root: root)
  try await store.save(current, replacing: nil)
  let keychain = MemoryProfileKeychain()
  let preparation = PhoneProfilePreparation(
    profiles: store, credentials: PhoneProfileCredentials(keychain: keychain))
  await #expect(throws: PhoneProfileStoreError.changed) {
    try await preparation.prepare(profile, credential: "fixture", replacing: nil)
  }
  let changed = PhoneProfile(
    id: profile.id, productAddress: profile.productAddress, instance: "other",
    nativeAddress: profile.nativeAddress, identity: profile.identity)
  await #expect(throws: PhoneProfileStoreError.changed) {
    try await preparation.prepare(changed, credential: "fixture", replacing: current)
  }
  #expect(keychain.inserts == 0)
  #expect(try await store.load() == current)
}

@Test func profileCredentialFailureKeepsPreparingInsteadOfPublishingPrepared() async throws {
  for failure: PhoneProfileCredentialError in [.locked, .unavailable(-50), .corrupt] {
    let root = profileTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let profile = exampleProfile()
    let store = PhoneProfileStore(root: root)
    let keychain = MemoryProfileKeychain(readFailure: failure)
    await #expect(throws: failure) {
      try await PhoneProfilePreparation(
        profiles: store, credentials: PhoneProfileCredentials(keychain: keychain)
      )
      .prepare(profile, credential: "fixture", replacing: nil)
    }
    let record = try await PhoneProfileStore(root: root).load()
    #expect(record?.profiles == [profile] && record?.selected == profile.id)
    #expect(keychain.inserts == 0)
  }
}

@Test func profileNativeDirectoryReopensUnderANewRuntimeRootWithoutChangingIdentity() async throws {
  let oldRoot = profileTestRoot()
  let newRoot = profileTestRoot()
  defer {
    try? FileManager.default.removeItem(at: oldRoot)
    try? FileManager.default.removeItem(at: newRoot)
  }
  let profile = exampleProfile()
  try FileManager.default.createDirectory(
    at: oldRoot, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
  let old = try await PhoneNativeLocations(root: oldRoot).prepare(profile)
  let first = try await NativeRetainedSessionFactory().open(old)
  #expect(try await first.localEnrollment() == nil)
  try await first.close()
  // Models a recreated sandbox/container path, preserving the UUID-relative native state.
  try FileManager.default.copyItem(at: oldRoot, to: newRoot)
  let current = try await PhoneNativeLocations(root: newRoot).prepare(profile)
  #expect(current.directory == old.directory && current.root != old.root)
  let reopened = try await NativeRetainedSessionFactory().open(current)
  #expect(try await reopened.localEnrollment() == nil)
  try await reopened.close()
}

@Test func profileFinalPublicationFailureRetainsCredentialAndRequiresConfirmedResume() async throws
{
  for mode in [FaultingProfileFiles.Mode.beforeSecondWrite, .afterSecondWrite] {
    let root = profileTestRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let profile = exampleProfile()
    let keychain = MemoryProfileKeychain()
    let credentials = PhoneProfileCredentials(keychain: keychain)
    let preparation = PhoneProfilePreparation(
      profiles: PhoneProfileStore(files: FaultingProfileFiles(root: root, mode: mode)),
      credentials: credentials)
    await #expect(
      throws: PhoneProfileStoreError.write(
        mode == .afterSecondWrite ? .published : .notPublished, .unavailable, reconciliation: nil)
    ) {
      try await preparation.prepare(profile, credential: "fixture", replacing: nil)
    }
    #expect(keychain.inserts == 1)
    let store = PhoneProfileStore(root: root)
    let saved = try await store.load()
    #expect(saved?.profiles[0].phase == (mode == .afterSecondWrite ? .prepared : .preparing))
    let resumed = try await PhoneProfilePreparation(profiles: store, credentials: credentials)
      .prepare(profile, credential: "fixture", replacing: saved)
    #expect(resumed.selected == profile.id && resumed.profiles[0].phase == .prepared)
    #expect(keychain.inserts == 1)
  }
}

@Test func profileNativeCreationRefusesParentAndLeafSymlinksBeforeOutsideEffects() async throws {
  for leaf in [false, true] {
    let root = profileTestRoot()
    let outside = profileTestRoot()
    defer {
      try? FileManager.default.removeItem(at: root)
      try? FileManager.default.removeItem(at: outside)
    }
    for directory in [root, outside] {
      try FileManager.default.createDirectory(
        at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    let profile = exampleProfile()
    let profiles = root.appendingPathComponent("NativeProfiles", isDirectory: true)
    if leaf {
      try FileManager.default.createDirectory(
        at: profiles, withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700])
    }
    let link = leaf ? profiles.appendingPathComponent(profile.id.uuidString.lowercased()) : profiles
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
    await #expect(throws: PhoneProfileStoreError.storage(.unavailable)) {
      try await PhoneNativeLocations(root: root).prepare(profile)
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == outside.path)
  }
}
