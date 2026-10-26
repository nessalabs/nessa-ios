import Foundation
import NessaNative

/// Created only from the retained parent's actual protected product child.
final class NativeGatewayProductExchange: GatewayProductExchange {
  private let parent: NativeSessionWorker
  private let product: NativeProductWorker
  init(parent: NativeSessionWorker, product: NativeProductWorker) {
    self.parent = parent
    self.product = product
  }
  func ready() async throws -> Data {
    try await product.ready { Data(try $0.json().utf8) }
  }
  /// The worker takes one submission at a time and turns a second away as `busy`, with
  /// nothing sent; the gateway client sends from several tasks at once (the inbox, a chat, the
  /// review reads). A submission is only the hand-over, so a refused one waits a moment and
  /// goes again rather than failing the person's request.
  func request(method: String, parameters: Data) async throws -> Data {
    while true {
      do { return try await submit(method: method, parameters: parameters) }
      catch NativeWorkerError.busy { try await Task.sleep(for: Self.busyRetry) }
    }
  }
  private static let busyRetry = Duration.milliseconds(2)
  private func submit(method: String, parameters: Data) async throws -> Data {
    try await product.request(method: method, paramsJson: String(decoding: parameters, as: UTF8.self)) {
      completion in
      switch completion.kind() {
      case .response:
        guard let json = try completion.responseJson() else { throw NessaGatewayError.invalidFrame }
        return Data(json.utf8)
      case .notDispatched, .uncertain:
        throw NativeProductDeliveryFailure(id: completion.id(), kind: completion.kind(),
          failure: completion.failure())
      }
    }
  }
  func events() async throws -> [Data] {
    try await product.events(timeoutMs: 1000) { try $0.framesJson().map { Data($0.utf8) } }
  }
  func requestClose() { product.requestClose(); parent.requestClose() }
  func close() async -> GatewayProductCloseObservation {
    requestClose()
    let productFailure: (any Error)?
    do { try await product.close(); productFailure = nil } catch { productFailure = error }
    do {
      return try await parent.closeObserved { observation, signalFailure in
        let parentFailure = observation.failure()
        let failure: (any Error)? =
          productFailure == nil && parentFailure == nil && signalFailure == nil ? nil
          : NativeProductCleanupFailure(product: productFailure, parent: parentFailure,
              signal: signalFailure)
        return .init(released: observation.released(), failure: failure)
      }
    } catch { return .init(released: false, failure: error) }
  }
}

struct NativeProductDeliveryFailure: Error, Sendable {
  let id: UInt64
  let kind: NativeProductCompletionKind
  let failure: NativeProductFailure?
}
struct NativeProductCleanupFailure: Error, Sendable {
  let product: (any Error)?
  let parent: NativeSessionFailure?
  let signal: (any Error)?
}
