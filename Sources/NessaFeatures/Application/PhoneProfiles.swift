import Foundation

public enum PhoneProfilePhase: String, Codable, Equatable, Sendable {
  case preparing, prepared, retired
}

public enum PhoneProfileRetirementReason: String, Codable, Equatable, Sendable {
  case userDiscarded
}

/// Stable setup identity and non-secret selectors. Neither endpoint establishes account authority.
public struct PhoneProfile: Codable, Equatable, Sendable {
  public let id: UUID
  public let phase: PhoneProfilePhase
  public let productAddress: String
  public let instance: String
  public let nativeAddress: String
  public let identity: GatewaySessionSnapshot.Identity
  public let pairingStatus: GatewayPairingStatus?
  public let nativeReceiver: String?
  public let lastNativeStatus: RetainedStatus?
  public let recoveredPurge: RetainedPurge?
  public let creationAttempt: UUID?
  public let retirementReason: PhoneProfileRetirementReason?
  public init(
    id: UUID, phase: PhoneProfilePhase = .preparing, productAddress: String, instance: String,
    nativeAddress: String, identity: GatewaySessionSnapshot.Identity,
    pairingStatus: GatewayPairingStatus? = nil, nativeReceiver: String? = nil,
    lastNativeStatus: RetainedStatus? = nil, recoveredPurge: RetainedPurge? = nil,
    creationAttempt: UUID? = nil, retirementReason: PhoneProfileRetirementReason? = nil
  ) {
    self.id = id
    self.phase = phase
    self.productAddress = productAddress
    self.instance = instance
    self.nativeAddress = nativeAddress
    self.identity = identity
    self.pairingStatus = pairingStatus
    self.nativeReceiver = nativeReceiver
    self.lastNativeStatus = lastNativeStatus
    self.recoveredPurge = recoveredPurge
    self.creationAttempt = creationAttempt
    self.retirementReason = retirementReason
  }
  var nativeDirectoryComponents: [String] { ["NativeProfiles", id.uuidString.lowercased()] }
  public var nativeDirectory: String { nativeDirectoryComponents.joined(separator: "/") }
  public var credentialReference: String { "profile-" + id.uuidString.lowercased() }
  public func changingPhase(to phase: PhoneProfilePhase) -> Self {
    Self(
      id: id, phase: phase, productAddress: productAddress, instance: instance,
      nativeAddress: nativeAddress, identity: identity, pairingStatus: pairingStatus,
      nativeReceiver: nativeReceiver, lastNativeStatus: lastNativeStatus,
      recoveredPurge: recoveredPurge, creationAttempt: creationAttempt,
      retirementReason: retirementReason)
  }
  public func recording(
    pairingStatus: GatewayPairingStatus?, nativeReceiver: String?,
    nativeStatus: RetainedStatus?, recoveredPurge: RetainedPurge?, retired: Bool,
    creationAttempt: UUID? = nil, retirementReason: PhoneProfileRetirementReason? = nil
  ) -> Self {
    Self(
      id: id, phase: retired ? .retired : phase,
      productAddress: productAddress, instance: instance, nativeAddress: nativeAddress,
      identity: identity, pairingStatus: pairingStatus, nativeReceiver: nativeReceiver,
      lastNativeStatus: nativeStatus, recoveredPurge: recoveredPurge,
      creationAttempt: creationAttempt ?? self.creationAttempt,
      retirementReason: retirementReason ?? self.retirementReason)
  }
  public var hasRetirementEvidence: Bool {
    if retirementReason == .userDiscarded, nativeReceiver == nil, lastNativeStatus == nil,
      recoveredPurge == nil, pairingStatus?.claimedDeviceKey == nil,
      pairingStatus?.credentialID == nil, pairingStatus?.receiver == nil
    {
      return true
    }
    if lastNativeStatus?.completionCaptured == true,
      lastNativeStatus?.receipt?.phase == .terminal
    {
      return true
    }
    guard let receiver = nativeReceiver,
      let purge = recoveredPurge ?? lastNativeStatus?.purge
    else { return false }
    return receiver.utf8.elementsEqual(purge.receiver.utf8)
  }
  public func sameSetup(as other: Self) -> Bool {
    id == other.id && identity == other.identity
      && productAddress.utf8.elementsEqual(other.productAddress.utf8)
      && instance.utf8.elementsEqual(other.instance.utf8)
      && nativeAddress.utf8.elementsEqual(other.nativeAddress.utf8)
  }
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.phase == rhs.phase && lhs.sameSetup(as: rhs) && lhs.pairingStatus == rhs.pairingStatus
      && sameText(lhs.nativeReceiver, rhs.nativeReceiver)
      && lhs.lastNativeStatus == rhs.lastNativeStatus && lhs.recoveredPurge == rhs.recoveredPurge
      && lhs.creationAttempt == rhs.creationAttempt && lhs.retirementReason == rhs.retirementReason
  }
  private static func sameText(_ lhs: String?, _ rhs: String?) -> Bool {
    switch (lhs, rhs) {
    case (nil, nil): return true
    case (.some(let a), .some(let b)): return a.utf8.elementsEqual(b.utf8)
    default: return false
    }
  }
}

/// One publication keeps selected identity and records together across crashes.
public struct PhoneProfiles: Codable, Equatable, Sendable {
  public let revision: UUID
  public let selected: UUID
  public let profiles: [PhoneProfile]
  public init(revision: UUID, selected: UUID, profiles: [PhoneProfile]) {
    self.revision = revision
    self.selected = selected
    self.profiles = profiles
  }
  public func validate() throws {
    guard Set(profiles.map(\.id)).count == profiles.count,
      profiles.contains(where: { $0.id == selected })
    else { throw PhoneProfileStoreError.invalid }
    for profile in profiles {
      do {
        if let owner = profile.pairingStatus {
          try PhonePairingCorrelation.validate(owner, profile: profile)
        }
        if let receipt = profile.lastNativeStatus?.receipt {
          try PhonePairingCorrelation.validate(receipt, profile: profile)
        }
      } catch { throw PhoneProfileStoreError.invalid }
      if profile.phase == .preparing {
        guard profile.pairingStatus == nil, profile.nativeReceiver == nil,
          profile.lastNativeStatus == nil, profile.recoveredPurge == nil,
          profile.creationAttempt == nil, profile.retirementReason == nil
        else { throw PhoneProfileStoreError.invalid }
      }
      guard profile.retirementReason == nil || profile.phase == .retired else {
        throw PhoneProfileStoreError.invalid
      }
      guard profile.phase != .retired || profile.hasRetirementEvidence else {
        throw PhoneProfileStoreError.invalid
      }
      if let receiver = profile.nativeReceiver {
        guard !receiver.isEmpty else { throw PhoneProfileStoreError.invalid }
        for observed in [
          profile.lastNativeStatus?.receipt?.receiver,
          profile.lastNativeStatus?.purge?.receiver, profile.recoveredPurge?.receiver,
        ].compactMap({ $0 }) {
          guard receiver.utf8.elementsEqual(observed.utf8) else {
            throw PhoneProfileStoreError.invalid
          }
        }
      }
    }
  }
  public func validate(replacing previous: Self?) throws {
    try validate()
    if let previous {
      try previous.validate()
      guard self == previous || revision != previous.revision else {
        throw PhoneProfileStoreError.invalid
      }
    }
    for prior in previous?.profiles ?? [] {
      guard let next = profiles.first(where: { $0.id == prior.id }), next.sameSetup(as: prior),
        prior.phase == .preparing || next.phase != .preparing,
        prior.phase != .retired || next.phase == .retired
      else { throw PhoneProfileStoreError.invalid }
      if let attempt = prior.creationAttempt {
        guard next.creationAttempt == attempt else { throw PhoneProfileStoreError.invalid }
      }
      if let reason = prior.retirementReason {
        guard next.retirementReason == reason else { throw PhoneProfileStoreError.invalid }
      }
      if let receiver = prior.nativeReceiver {
        guard receiver.utf8.elementsEqual((next.nativeReceiver ?? "").utf8) else {
          throw PhoneProfileStoreError.invalid
        }
      }
      if let original = prior.pairingStatus {
        guard let updated = next.pairingStatus,
          original.invitationID == updated.invitationID, original.consentID == updated.consentID,
          original.generation == updated.generation,
          original.consentClass.utf8.elementsEqual(updated.consentClass.utf8),
          original.grant == updated.grant, original.createdAtMs == updated.createdAtMs,
          original.expiresAtMs == updated.expiresAtMs
        else { throw PhoneProfileStoreError.invalid }
      }
    }
    for next in profiles where previous?.profiles.contains(where: { $0.id == next.id }) != true {
      guard next.phase == .preparing else { throw PhoneProfileStoreError.invalid }
    }
  }
}

public enum PhoneProfileStorageFailure: Equatable, Sendable { case quota, unavailable }
public enum PhoneProfilePublication: Equatable, Sendable { case notPublished, published, uncertain }
public enum PhoneProfileStoreError: Error, Equatable, Sendable {
  case invalid, corrupt, changed
  case storage(PhoneProfileStorageFailure)
  /// Readback describes visibility, not durable fsync success. No setup effects may proceed.
  case write(
    PhoneProfilePublication, PhoneProfileStorageFailure, reconciliation: PhoneProfileStorageFailure?
  )
}
public protocol PhoneProfileStoring: Sendable {
  func load() async throws -> PhoneProfiles?
  func save(_ next: PhoneProfiles, replacing expected: PhoneProfiles?) async throws
}
public enum PhoneProfileCredentialError: Error, Equatable, Sendable {
  case missing, locked, corrupt, conflict
  case unavailable(Int32)
}
public protocol PhoneProfileCredentialStoring: Sendable {
  func load(reference: String) async throws -> String
  func insertOrVerify(_ credential: String, reference: String) async throws
}
public protocol PhoneNativeLocationPreparing: Sendable {
  func prepare(_ profile: PhoneProfile) async throws -> RetainedSessionLocation
}
