import Foundation

/// Opens a product connection to the paired Mac over its native link. Behind
/// a port so the native side is injected. The exchange owns what it opened and
/// releases it when it closes.
protocol LinkedProductOpening: Sendable {
  func open(_ desktop: LinkedDesktop, instance: String) async throws
    -> any GatewayProductExchange
}

/// A repository that can serve the product session over a paired Mac's native
/// link instead of a gateway address.
protocol LinkedProductConnecting: Sendable {
  func connectLinked(_ exchange: any GatewayProductExchange, scope: PhoneCacheScope)
    async throws -> GatewayConnectionLease
  /// Returns once every product connection it closed has released its native
  /// session, so that session's directory can be removed.
  func drainLinked() async throws
}

/// Product sessions to the paired Mac, each held by `DesktopLinking` until it
/// closes, so forgetting the Mac never removes a directory still in use.
struct LinkedDesktopProducts: LinkedProductOpening {
  let linking: DesktopLinking
  let native: any LinkedProductOpening
  func open(_ desktop: LinkedDesktop, instance: String) async throws
    -> any GatewayProductExchange
  {
    try await linking.openProduct(desktop, instance: instance, through: native)
  }
}
