import Foundation

public enum PhoneProfilePhase: String, Codable, Equatable, Sendable { case preparing, prepared }

/// Stable setup identity and non-secret selectors. Neither endpoint establishes account authority.
public struct PhoneProfile: Codable, Equatable, Sendable {
  public let id: UUID
  public let phase: PhoneProfilePhase
  public let productAddress: String
  public let instance: String
  public let nativeAddress: String
  public let identity: GatewaySessionSnapshot.Identity
  public init(
    id: UUID, phase: PhoneProfilePhase = .preparing, productAddress: String, instance: String,
    nativeAddress: String, identity: GatewaySessionSnapshot.Identity
  ) {
    self.id = id
    self.phase = phase
    self.productAddress = productAddress
    self.instance = instance
    self.nativeAddress = nativeAddress
    self.identity = identity
  }
  var nativeDirectoryComponents: [String] { ["NativeProfiles", id.uuidString.lowercased()] }
  public var nativeDirectory: String { nativeDirectoryComponents.joined(separator: "/") }
  public var credentialReference: String { "profile-" + id.uuidString.lowercased() }
  public func changingPhase(to phase: PhoneProfilePhase) -> Self {
    Self(
      id: id, phase: phase, productAddress: productAddress, instance: instance,
      nativeAddress: nativeAddress, identity: identity)
  }
  public func sameSetup(as other: Self) -> Bool {
    id == other.id && identity == other.identity
      && productAddress.utf8.elementsEqual(other.productAddress.utf8)
      && instance.utf8.elementsEqual(other.instance.utf8)
      && nativeAddress.utf8.elementsEqual(other.nativeAddress.utf8)
  }
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.phase == rhs.phase && lhs.sameSetup(as: rhs)
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
        prior.phase != .prepared || next.phase == .prepared
      else { throw PhoneProfileStoreError.invalid }
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
