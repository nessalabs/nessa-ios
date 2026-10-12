import Foundation

/// Local socket ownership, never a server credential or retained checkpoint.
public struct GatewayConnectionLease: Sendable, Equatable {
  private let id = UUID()
  public init() {}
}
public protocol ConnectionLeasing: Sendable {
  func connectWithLease(address: String, credential: String, instance: String) async throws
    -> GatewayConnectionLease
  func retire(_ lease: GatewayConnectionLease) async
}
