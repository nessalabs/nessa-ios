import Foundation
import Security
import Testing

@testable import NessaFeatures

@Test func profileKeychainIsImmutableAndDistinguishesMissingCorruptLockedAndConflict() async throws
{
  let reference = exampleProfile().credentialReference
  let keychain = MemoryProfileKeychain()
  let store = PhoneProfileCredentials(keychain: keychain)
  await #expect(throws: PhoneProfileCredentialError.missing) {
    try await store.load(reference: reference)
  }
  try await store.insertOrVerify("fixture", reference: reference)
  try await store.insertOrVerify("fixture", reference: reference)
  #expect(keychain.inserts == 1)
  await #expect(throws: PhoneProfileCredentialError.corrupt) {
    try await store.insertOrVerify("", reference: reference)
  }

  #expect(try await store.load(reference: reference) == "fixture")
  await #expect(throws: PhoneProfileCredentialError.conflict) {
    try await store.insertOrVerify("other", reference: reference)
  }
  #expect(try await store.load(reference: reference) == "fixture")
  for bytes in [Data(), Data([0xff])] {
    let broken = PhoneProfileCredentials(
      keychain: MemoryProfileKeychain(records: [reference: bytes]))
    await #expect(throws: PhoneProfileCredentialError.corrupt) {
      try await broken.load(reference: reference)
    }
    await #expect(throws: PhoneProfileCredentialError.corrupt) {
      try await broken.insertOrVerify("fixture", reference: reference)
    }
  }
  for failure: PhoneProfileCredentialError in [.locked, .unavailable(-50)] {
    let unavailable = PhoneProfileCredentials(keychain: MemoryProfileKeychain(readFailure: failure))
    await #expect(throws: failure) { try await unavailable.load(reference: reference) }
    await #expect(throws: failure) {
      try await unavailable.insertOrVerify("fixture", reference: reference)
    }
  }
  // Another process wins SecItemAdd after our absent read. Its bytes must not be overwritten.
  let race = PhoneProfileCredentials(
    keychain: MemoryProfileKeychain(competing: Data("different".utf8)))
  await #expect(throws: PhoneProfileCredentialError.conflict) {
    try await race.insertOrVerify("fixture", reference: reference)
  }
  #expect(try await race.load(reference: reference) == "different")
}

@Test func realProfileKeychainReopensExactDisposableItemWithoutUsingTheProductCredential()
  async throws
{
  let reference = exampleProfile().credentialReference
  defer {
    SecItemDelete(
      [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: PhoneProfileKeychainIdentity.service,
        kSecAttrAccount as String: reference,
      ] as CFDictionary)
  }
  try await PhoneProfileCredentials().insertOrVerify(
    "disposable-profile-fixture", reference: reference)
  #expect(
    try await PhoneProfileCredentials().load(reference: reference) == "disposable-profile-fixture")
  try await PhoneProfileCredentials().insertOrVerify(
    "disposable-profile-fixture", reference: reference)
  await #expect(throws: PhoneProfileCredentialError.conflict) {
    try await PhoneProfileCredentials().insertOrVerify(
      "changed-disposable-fixture", reference: reference)
  }
  #expect(
    try await PhoneProfileCredentials().load(reference: reference) == "disposable-profile-fixture")
}

@Test func profileAuthenticatedIdentityKeepsEveryOpaqueFieldByteExact() {
  let composed = "é"
  let decomposed = "e\u{301}"
  #expect(composed == decomposed)
  let same = profileIdentity(Array(repeating: composed, count: 6))
  for field in 0..<6 {
    var values = Array(repeating: composed, count: 6)
    values[field] = decomposed
    #expect(same != profileIdentity(values))
  }
  let a = GatewaySessionSnapshot.Resource(organizationID: composed, id: composed)
  #expect(a != .init(organizationID: decomposed, id: composed))
  #expect(a != .init(organizationID: composed, id: decomposed))
  let grant = GatewaySessionSnapshot.Grant(action: composed, resource: a)
  #expect(grant != .init(action: decomposed, resource: a))
  let snapshot = GatewaySessionSnapshot(
    identity: same, expiresAt: UInt64.max, grants: [grant], methods: [composed])
  #expect(
    snapshot != .init(identity: same, expiresAt: UInt64.max, grants: [grant], methods: [decomposed])
  )
}
