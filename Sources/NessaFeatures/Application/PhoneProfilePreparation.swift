import Foundation

/// Stateless preparation; the enclosing setup coordinator owns operation admission.
public struct PhoneProfilePreparation: Sendable {
  private let profiles: any PhoneProfileStoring
  private let credentials: any PhoneProfileCredentialStoring
  private let revision: @Sendable () -> UUID
  public init(
    profiles: any PhoneProfileStoring, credentials: any PhoneProfileCredentialStoring,
    revision: @escaping @Sendable () -> UUID = { UUID() }
  ) {
    self.profiles = profiles
    self.credentials = credentials
    self.revision = revision
  }
  /// A failed write or credential operation leaves its original profile available for recovery.
  public func prepare(
    _ desired: PhoneProfile, credential: String, replacing expected: PhoneProfiles?
  ) async throws -> PhoneProfiles {
    var records = expected?.profiles ?? []
    if let existing = records.first(where: { $0.id == desired.id }) {
      guard existing.sameSetup(as: desired) else { throw PhoneProfileStoreError.changed }
    } else {
      guard desired.phase == .preparing else { throw PhoneProfileStoreError.invalid }
      records.append(desired)
    }
    let preparing = PhoneProfiles(revision: revision(), selected: desired.id, profiles: records)
    // Even recovery republishes successfully before Keychain effects: readback alone is not durability.
    try await profiles.save(preparing, replacing: expected)
    try await credentials.insertOrVerify(credential, reference: desired.credentialReference)
    let prepared = PhoneProfiles(
      revision: revision(), selected: desired.id,
      profiles: records.map { $0.id == desired.id ? $0.changingPhase(to: .prepared) : $0 })
    try await profiles.save(prepared, replacing: preparing)
    return prepared
  }
}
