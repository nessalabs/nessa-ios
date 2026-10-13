import Foundation

public enum PhoneSnapshotMarkerFailure: Error, Equatable, Sendable {
  case corrupt, quota, unavailable
}

public enum PhoneSnapshotWithdrawalError: Error, Equatable, Sendable {
  case unsupported
  case marker(PhoneSnapshotMarkerFailure)
  /// Readback establishes visibility only; every failed write blocks completion.
  case write(
    PhoneProfilePublication, PhoneSnapshotMarkerFailure,
    reconciliation: PhoneSnapshotMarkerFailure?)
}

/// Irreversible suppression of a derived display scope, not native receiver authority.
public protocol PhoneSnapshotWithdrawing: Sendable {
  func withdraw(_ scope: PhoneCacheScope) async throws
}
