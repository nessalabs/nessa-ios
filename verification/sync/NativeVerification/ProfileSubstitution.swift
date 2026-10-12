import Foundation
import NessaFeatures

// Ordinary imports can replace all profile boundaries without Keychain/files/native handles.
private struct ProfileStoreSubstitute: PhoneProfileStoring {
  func load() async throws -> PhoneProfiles? { nil }
  func save(_ next: PhoneProfiles, replacing expected: PhoneProfiles?) async throws {
    try next.validate(replacing: expected)
  }
}
private struct ProfileCredentialSubstitute: PhoneProfileCredentialStoring {
  func load(reference: String) async throws -> String { throw PhoneProfileCredentialError.missing }
  func insertOrVerify(_ credential: String, reference: String) async throws {}
}
private struct ProfileLocationSubstitute: PhoneNativeLocationPreparing {
  func prepare(_ profile: PhoneProfile) async throws -> RetainedSessionLocation {
    .init(
      root: "/explicit-test-root", directory: profile.nativeDirectory,
      address: profile.nativeAddress)
  }
}
private func profileSubstitution() async throws {
  let profile = PhoneProfile(
    id: UUID(), productAddress: "ws://127.0.0.1:9/session", instance: "test",
    nativeAddress: "127.0.0.1:9",
    identity: .init(
      gatewayID: "test", principalID: "test",
      organizationID: "test", membershipID: "test", credentialID: "test", audienceID: "test"))
  _ = try await PhoneProfilePreparation(
    profiles: ProfileStoreSubstitute(), credentials: ProfileCredentialSubstitute()
  )
  .prepare(profile, credential: "disposable-test", replacing: nil)
  _ = try await ProfileLocationSubstitute().prepare(profile)
}
