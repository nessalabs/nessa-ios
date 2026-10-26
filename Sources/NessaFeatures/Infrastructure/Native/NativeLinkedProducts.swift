import Foundation
import NessaNative

/// The paired Mac's product session: a native session on that Mac's
/// directory, holding the key and credential pairing issued, opens the product
/// child, and the exchange closes both.
struct NativeLinkedProducts: LinkedProductOpening {
  let locations: any LinkedDesktopLocating
  func open(_ desktop: LinkedDesktop, instance: String) async throws
    -> any GatewayProductExchange
  {
    let location = try await locations.prepare(id: desktop.id, address: desktop.address)
    return try await NativeRetainedExecutor.run {
      let worker = try await NativeSessionWorker.open(
        root: location.root, directory: location.directory, address: location.address,
        tunnel: desktop.tunnel)
      do {
        let product = try await worker.openProduct(instance: instance)
        return NativeGatewayProductExchange(parent: worker, product: product)
      } catch {
        try? await worker.close()
        throw error
      }
    }
  }
}
