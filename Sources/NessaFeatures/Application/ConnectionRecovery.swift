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
    if let error = (error as? GatewayProductRejection)?.behavior ?? error as? NessaGatewayError {
      switch error {
      case .disconnected, .timeout: return true
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
