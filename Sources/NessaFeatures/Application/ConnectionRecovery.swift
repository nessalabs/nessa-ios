import Foundation

public protocol RecoveryWaiting: Sendable {
  func wait(for duration: Duration) async throws
}
/// Recovery retries reads/connections only; it never replays a command.
public struct ConnectionRecovery: Sendable {
  private let waiting: any RecoveryWaiting
  public init(waiting: any RecoveryWaiting) { self.waiting = waiting }
  public func run(attempt: @Sendable () async throws -> Void) async throws {
    var failures = 0
    while true {
      try Task.checkCancellation()
      do {
        try await attempt()
        return
      } catch {
        guard Self.retryable(error) else { throw error }
        try Task.checkCancellation()
        let milliseconds = min(15_000, 500 << min(failures, 5))
        failures += 1
        try await waiting.wait(for: .milliseconds(milliseconds))
      }
    }
  }
  public static func retryable(_ error: Error) -> Bool {
    // The paired Mac's link: whatever is not the Mac's or this phone's settled answer (turned
    // away, a spent code, storage this phone can't keep) is the link not getting through, which
    // trying again mends once the phone is back on the Mac's network.
    if let error = error as? RetainedSessionError {
      switch error {
      case .busy, .closed: return true
      case .session:
        switch DesktopLinking.failure(error) {
        case .denied, .wrongCode, .expired, .cancelled, .storage: return false
        case .noDesktop, .unreachable, .other: return true
        }
      // A call the native refused as malformed, or one that was cancelled, goes the same way
      // however often it is tried.
      case .invalidArgument, .ownerPreparation, .view, .cancelled, .bridge: return false
      }
    }
    if let error = (error as? GatewayProductRejection)?.behavior ?? error as? NessaGatewayError {
      switch error {
      case .disconnected, .timeout: return true
      case .revoked: return false
      default: return false
      }
    }
    guard let error = error as? URLError else { return false }
    switch error.code {
    case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost,
      .cannotFindHost, .dnsLookupFailed:
      return true
    default: return false
    }
  }
}
