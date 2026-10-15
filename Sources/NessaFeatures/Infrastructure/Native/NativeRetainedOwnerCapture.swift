import Foundation
import NessaNative

extension NativeRetainedCapture {
  static func capture(_ value: NativeOwnerAdoptionPhase) -> RetainedOwnerAdoptionPhase {
    switch value {
    case .originalRead: return .originalRead
    case .bindLineage: return .bindLineage
    case .publishEnrollment: return .publishEnrollment
    }
  }

  static func capture(_ value: NativeOwnerArgumentFailure) -> RetainedOwnerArgumentFailure {
    switch value {
    case .tooLarge: return .tooLarge
    case .json: return .json
    case .requestId: return .requestId
    case .length: return .length
    case .octet: return .octet
    case .source: return .source
    case .endpoint: return .endpoint
    case .original: return .original
    case .consent: return .consent
    case .copyTooLarge: return .copyTooLarge
    case .copyInvalid: return .copyInvalid
    }
  }

  static func capture(_ value: NativeOwnerEnrollmentKind) -> RetainedOwnerEnrollmentKind {
    switch value {
    case .pending: return .pending
    case .issued: return .issued
    }
  }

  static func capture(_ value: NativeOwnerPreparationFailureKind)
    -> RetainedOwnerPreparationFailureKind
  {
    switch value {
    case .crypto: return .crypto
    case .`private`: return .`private`
    case .missing: return .missing
    case .incomplete: return .incomplete
    }
  }

  static func capture(_ value: NativeOwnerRecoveryFailureKind) -> RetainedOwnerRecoveryFailureKind {
    switch value {
    case .preparation: return .preparation
    case .native: return .native
    }
  }

  static func capture(_ value: NativeOwnerSettlementFailureKind)
    -> RetainedOwnerSettlementFailureKind
  {
    switch value {
    case .preparation: return .preparation
    case .adoption: return .adoption
    case .savedRecord: return .savedRecord
    case .end: return .end
    case .terminalRecord: return .terminalRecord
    case .correlation: return .correlation
    }
  }

  static func capture(_ value: NativeOwnerSettlementKind) -> RetainedOwnerSettlementKind {
    switch value {
    case .adopted: return .adopted
    case .ended: return .ended
    }
  }

  static func capture(_ value: NativeProductFailureKind) -> RetainedProductFailureKind {
    switch value {
    case .invalidLimits: return .invalidLimits
    case .invalidRequest: return .invalidRequest
    case .unadvertisedMethod: return .unadvertisedMethod
    case .capacity: return .capacity
    case .requestTooLarge: return .requestTooLarge
    case .responseTooLarge: return .responseTooLarge
    case .timedOut: return .timedOut
    case .cancelled: return .cancelled
    case .transport: return .transport
    case .closed: return .closed
    case .nativeHandshake: return .nativeHandshake
    case .productRefused: return .productRefused
    case .authentication: return .authentication
    case .`protocol`: return .`protocol`
    case .correlation: return .correlation
    case .workerPanicked: return .workerPanicked
    case .notReady: return .notReady
    }
  }

  static func capture(_ value: NativeProductCloseReason) -> RetainedProductCloseReason {
    switch value {
    case .authenticationFailed: return .authenticationFailed
    case .credentialRevoked: return .credentialRevoked
    case .credentialExpired: return .credentialExpired
    case .authorizationLost: return .authorizationLost
    case .protocolIncompatible: return .protocolIncompatible
    case .handshakeTimeout: return .handshakeTimeout
    case .temporaryUnavailable: return .temporaryUnavailable
    case .gatewayRestarting: return .gatewayRestarting
    case .gatewayOverloaded: return .gatewayOverloaded
    case .serverShutdown: return .serverShutdown
    case .transportInterrupted: return .transportInterrupted
    }
  }

  static func capture(_ value: any NativeOwnerAdoptionProtocol) -> RetainedOwnerAdoption {
    return RetainedOwnerAdoption(
      kind: capture(value.kind()),
      publicIntent: capture(value.publicIntent())
    )
  }

  static func capture(_ value: any NativeOwnerAdoptionFailureProtocol)
    -> RetainedOwnerAdoptionFailure
  {
    return RetainedOwnerAdoptionFailure(
      acknowledgedLineage: value.acknowledgedLineage().map { capture($0) },
      phase: capture(value.phase()),
      privateState: capture(value.privateState())
    )
  }

  static func capture(_ value: any NativeOwnerPhonePreparationProtocol)
    -> RetainedOwnerPhonePreparation
  {
    let originalJson: RetainedOwnerOriginalCopy
    do { originalJson = .copied(Data(try value.originalJson().utf8)) } catch {
      originalJson = .failed(preparationError(error))
    }
    return RetainedOwnerPhonePreparation(
      deviceKey: value.deviceKey(),
      digest: value.digest(),
      originalJson: originalJson,
      requestId: value.requestId(),
      signature: value.signature()
    )
  }

  static func capture(_ value: any NativeOwnerPreparationFailureProtocol)
    -> RetainedOwnerPreparationFailure
  {
    return RetainedOwnerPreparationFailure(
      crypto: value.crypto().map { capture($0) },
      kind: capture(value.kind()),
      privateState: value.privateState().map { capture($0) }
    )
  }

  static func capture(_ value: any NativeOwnerRecoveredProtocol) -> RetainedOwnerRecovered {
    return RetainedOwnerRecovered(
      preparation: capture(value.preparation()),
      receipt: capture(value.receipt())
    )
  }

  static func capture(_ value: any NativeOwnerRecoveryFailureProtocol)
    -> RetainedOwnerRecoveryFailure
  {
    return RetainedOwnerRecoveryFailure(
      kind: capture(value.kind()),
      native: value.native().map { capture($0) },
      preparation: value.preparation().map { capture($0) }
    )
  }

  static func capture(_ value: any NativeOwnerSettlementFailureProtocol)
    -> RetainedOwnerSettlementFailure
  {
    return RetainedOwnerSettlementFailure(
      adoption: value.adoption().map { capture($0) },
      correlation: value.correlation().map { capture($0) },
      end: value.end().map { capture($0) },
      kind: capture(value.kind()),
      preparation: value.preparation().map { capture($0) },
      reportedAdoption: value.reportedAdoption().map { capture($0) },
      selection: value.selection().map { capture($0) }
    )
  }

  static func capture(_ value: any NativeOwnerStatusProtocol) -> RetainedOwnerStatus {
    return RetainedOwnerStatus(
      adoption: value.adoption().map { capture($0) },
      completionCaptured: value.completionCaptured(),
      purge: value.purge().map { capture($0) },
      purgeFailure: value.purgeFailure().map { capture($0) },
      recovered: value.recovered().map { capture($0) },
      recoveryFailure: value.recoveryFailure().map { capture($0) },
      settlementFailure: value.settlementFailure().map { capture($0) },
      settlementKind: value.settlementKind().map { capture($0) }
    )
  }

  static func capture(_ value: any NativeProductFailureProtocol) -> RetainedProductFailure {
    return RetainedProductFailure(
      closeReason: value.closeReason().map { capture($0) },
      kind: capture(value.kind())
    )
  }

  static func preparationError(_ error: any Error) -> RetainedOwnerPreparationCallFailure {
    guard let error = error as? NativeOwnerPreparationCallError else { return .bridge }
    switch error {
    case .Argument(let failure): return .argument(capture(failure))
    case .Session(let failure): return .session(capture(failure))
    case .Preparation(let failure): return .preparation(capture(failure))
    }
  }
}
