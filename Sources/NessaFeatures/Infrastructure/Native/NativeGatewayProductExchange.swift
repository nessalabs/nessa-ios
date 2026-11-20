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
    try await NativeProductLinkFailure.worded { try await product.ready { Data(try $0.json().utf8) } }
  }
  func request(method: String, parameters: Data) async throws -> Data {
    try await NativeProductLinkFailure.worded {
      try await product.request(
        method: method, paramsJson: String(decoding: parameters, as: UTF8.self)
      ) { completion in
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
  }
  func events() async throws -> [Data] {
    try await NativeProductLinkFailure.worded {
      try await product.events(timeoutMs: 1000) { try $0.framesJson().map { Data($0.utf8) } }
    }
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

/// A call over the paired Mac's product link that failed in the native layer. The person reads
/// plain words; the native failure stays in `underlying` for diagnostics. The generated native
/// errors describe themselves as their Swift type dump ("NessaNative.NativeProductCallError…"),
/// so none of them may reach the app without passing through here.
struct NativeProductLinkFailure: LocalizedError, Sendable {
  let underlying: any Error
  var errorDescription: String? { Self.sentence(underlying) }

  /// Runs one native call, rewording whatever it throws. Cancellation and the app's own
  /// gateway errors pass through unchanged, so callers still recognise them.
  static func worded<Value>(_ call: () async throws -> Value) async throws -> Value {
    do { return try await call() } catch {
      if error is CancellationError || error is NessaGatewayError { throw error }
      throw NativeProductLinkFailure(underlying: error)
    }
  }

  static func sentence(_ error: any Error) -> String {
    if let capture = error as? NativeProductCaptureFailure { return sentence(capture.underlying) }
    if let gateway = error as? NessaGatewayError { return gateway.localizedDescription }
    if let delivery = error as? NativeProductDeliveryFailure {
      if let failure = delivery.failure { return sentence(failure.kind()) }
      return delivery.kind == .notDispatched
        ? "Your Mac didn’t get this. Try again."
        : "Your Mac may not have got this. Check the chat before trying again."
    }
    if let call = error as? NativeProductCallError, case .Product(let failure) = call {
      return sentence(failure.kind())
    }
    if let worker = error as? NativeWorkerError {
      switch worker {
      case .busy: return "Your Mac is busy. Try again in a moment."
      case .closed: return "Can’t reach your Mac right now."
      }
    }
    return "Something went wrong talking to your Mac. Try again."
  }

  static func sentence(_ kind: NativeProductFailureKind) -> String {
    switch kind {
    case .timedOut: "Your Mac didn’t answer in time. Try again."
    case .transport, .closed, .notReady, .nativeHandshake, .cancelled:
      "Can’t reach your Mac right now."
    case .capacity: "Your Mac is busy. Try again in a moment."
    case .requestTooLarge: "That’s too large to send to your Mac."
    case .responseTooLarge: "Your Mac’s answer was too large for this phone."
    case .authentication, .productRefused: "Your Mac turned this away."
    case .invalidLimits, .invalidRequest, .unadvertisedMethod, .`protocol`, .correlation:
      "This phone and your Mac don’t understand each other. Update Nessa on both."
    case .workerPanicked: "Something went wrong talking to your Mac. Try again."
    }
  }
}
