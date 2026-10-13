import Foundation

public enum PhoneRetainedTranscriptRead: Sendable {
  case available(PhoneScopedRetention<RetainedTranscript>)
  case failed(any Error)
}

public struct PhoneRetainedDisplayFailure: Error, Sendable {
  public let snapshot: PhoneProfileSnapshot
  public let catalogue: PhoneRetainedCatalogue?
  public let transcripts: [String: PhoneRetainedTranscriptRead]
  public let refreshFailure: (any Error)?
  public let underlying: any Error
  public init(
    snapshot: PhoneProfileSnapshot, catalogue: PhoneRetainedCatalogue?,
    transcripts: [String: PhoneRetainedTranscriptRead], refreshFailure: (any Error)?,
    underlying: any Error
  ) {
    self.snapshot = snapshot
    self.catalogue = catalogue
    self.transcripts = transcripts
    self.refreshFailure = refreshFailure
    self.underlying = underlying
  }
}

/// Complete admitted observations; enumeration and UI epochs are not native checkpoints.
public struct PhoneRetainedDisplay: Sendable {
  public let snapshot: PhoneProfileSnapshot
  public let catalogue: PhoneRetainedCatalogue
  public let transcripts: [String: PhoneRetainedTranscriptRead]
  public let refreshFailure: (any Error)?
  /// Cached readability is distinct from a successful refresh on the current product source.
  /// Native status/read owners decide permissions; this only requires their positive results.
  public func commandReady(on lease: GatewayConnectionLease?) -> Bool {
    guard let lease, snapshot.source?.connection == lease, snapshot.profile.phase == .prepared,
      refreshFailure == nil, let refresh = snapshot.nativeRefresh,
      refresh.selectionFailure == nil, let read = refresh.read,
      read.failure == nil, read.complete != nil
    else { return false }
    // The native driver rechecks after a refused read, not after every successful read.
    let statuses = [refresh.initial] + (refresh.recheck.map { [$0] } ?? [])
    return statuses.allSatisfy {
      $0.completionCaptured && $0.failure == nil && $0.receipt != nil && $0.purgeFailure == nil
    }
  }
  public init(
    snapshot: PhoneProfileSnapshot, catalogue: PhoneRetainedCatalogue,
    transcripts: [String: PhoneRetainedTranscriptRead], refreshFailure: (any Error)?
  ) {
    self.snapshot = snapshot
    self.catalogue = catalogue
    self.transcripts = transcripts
    self.refreshFailure = refreshFailure
  }
}
