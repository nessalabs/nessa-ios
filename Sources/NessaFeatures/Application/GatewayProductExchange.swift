import Foundation

/// The issued device owns transport correlation, deadlines and admission. The
/// repository owns application commands, subscriptions and its connection lease.
protocol GatewayProductExchange: AnyObject, Sendable {
  func ready() async throws -> Data
  func request(method: String, parameters: Data) async throws -> Data
  func events() async throws -> [Data]
  /// Fence and wake blocked native calls synchronously, before waiting for drain.
  func requestClose()
  /// Await physical cleanup independently of an observer's cancellation.
  func close() async -> GatewayProductCloseObservation
}

/// `released` comes from the native parent cleanup owner, independently of its
/// original failure. An error name or a successful wake cannot establish it.
struct GatewayProductCloseObservation: Sendable {
  let released: Bool
  let failure: (any Error)?
}

/// Preserve the canonical rejection independently of its application behavior.
/// Diagnostics never select retry or command-delivery policy.
struct GatewayProductRejection: LocalizedError, Sendable {
  let code: String
  let diagnostic: String
  let details: Data?
  let behavior: NessaGatewayError
  var errorDescription: String? { behavior.errorDescription }
}

struct GatewayProductConnectionFailure: Error, Sendable {
  let underlying: any Error
  let cleanup: any Error
}
