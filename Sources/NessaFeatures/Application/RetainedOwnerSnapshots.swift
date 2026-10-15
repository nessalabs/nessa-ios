import Foundation

/// Public native observations. Historical recovery and adoption are not live authority.
public enum RetainedOwnerAdoptionPhase: String, Codable, Equatable, Sendable {
  case originalRead
  case bindLineage
  case publishEnrollment
}

public enum RetainedOwnerArgumentFailure: String, Codable, Equatable, Sendable {
  case tooLarge
  case json
  case requestId
  case length
  case octet
  case source
  case endpoint
  case original
  case consent
  case copyTooLarge
  case copyInvalid
}

public enum RetainedOwnerEnrollmentKind: String, Codable, Equatable, Sendable {
  case pending
  case issued
}

public enum RetainedOwnerPreparationFailureKind: String, Codable, Equatable, Sendable {
  case crypto
  case `private`
  case missing
  case incomplete
}

public enum RetainedOwnerRecoveryFailureKind: String, Codable, Equatable, Sendable {
  case preparation
  case native
}

public enum RetainedOwnerSettlementFailureKind: String, Codable, Equatable, Sendable {
  case preparation
  case adoption
  case savedRecord
  case end
  case terminalRecord
  case correlation
}

public enum RetainedOwnerSettlementKind: String, Codable, Equatable, Sendable {
  case adopted
  case ended
}

public enum RetainedProductFailureKind: String, Codable, Equatable, Sendable {
  case invalidLimits
  case invalidRequest
  case unadvertisedMethod
  case capacity
  case requestTooLarge
  case responseTooLarge
  case timedOut
  case cancelled
  case transport
  case closed
  case nativeHandshake
  case productRefused
  case authentication
  case `protocol`
  case correlation
  case workerPanicked
  case notReady
}

public enum RetainedProductCloseReason: String, Codable, Equatable, Sendable {
  case authenticationFailed
  case credentialRevoked
  case credentialExpired
  case authorizationLost
  case protocolIncompatible
  case handshakeTimeout
  case temporaryUnavailable
  case gatewayRestarting
  case gatewayOverloaded
  case serverShutdown
  case transportInterrupted
}

/// Keeps a bounded copy refusal beside independently captured public proof fields.
public indirect enum RetainedOwnerOriginalCopy: Codable, Equatable, Sendable {
  case copied(Data)
  case failed(RetainedOwnerPreparationCallFailure)
}

public indirect enum RetainedOwnerPreparationCallFailure: Error, Codable, Equatable, Sendable {
  case argument(RetainedOwnerArgumentFailure)
  case session(RetainedSessionFailure)
  case preparation(RetainedOwnerPreparationFailure)
  case bridge
}

public struct RetainedOwnerAdoption: Codable, Equatable, Sendable {
  public let kind: RetainedOwnerEnrollmentKind
  public let publicIntent: RetainedPublicIntent
  public init(
    kind: RetainedOwnerEnrollmentKind, publicIntent: RetainedPublicIntent
  ) {
    self.kind = kind
    self.publicIntent = publicIntent
  }
}

public struct RetainedOwnerAdoptionFailure: Codable, Equatable, Sendable {
  public let acknowledgedLineage: RetainedPublicIntent?
  public let phase: RetainedOwnerAdoptionPhase
  public let privateState: RetainedPrivateStateFailure
  public init(
    acknowledgedLineage: RetainedPublicIntent?, phase: RetainedOwnerAdoptionPhase,
    privateState: RetainedPrivateStateFailure
  ) {
    self.acknowledgedLineage = acknowledgedLineage
    self.phase = phase
    self.privateState = privateState
  }
}

public struct RetainedOwnerPhonePreparation: Codable, Equatable, Sendable {
  public let deviceKey: Data
  public let digest: Data
  public let originalJson: RetainedOwnerOriginalCopy
  public let requestId: Data
  public let signature: Data
  public init(
    deviceKey: Data, digest: Data, originalJson: RetainedOwnerOriginalCopy, requestId: Data,
    signature: Data
  ) {
    self.deviceKey = deviceKey
    self.digest = digest
    self.originalJson = originalJson
    self.requestId = requestId
    self.signature = signature
  }
}

public struct RetainedOwnerPreparationFailure: Codable, Equatable, Sendable {
  public let crypto: RetainedCryptoFailure?
  public let kind: RetainedOwnerPreparationFailureKind
  public let privateState: RetainedPrivateStateFailure?
  public init(
    crypto: RetainedCryptoFailure?, kind: RetainedOwnerPreparationFailureKind,
    privateState: RetainedPrivateStateFailure?
  ) {
    self.crypto = crypto
    self.kind = kind
    self.privateState = privateState
  }
}

public struct RetainedOwnerRecovered: Codable, Equatable, Sendable {
  public let preparation: RetainedOwnerPhonePreparation
  public let receipt: RetainedEnrollmentReceipt
  public init(
    preparation: RetainedOwnerPhonePreparation, receipt: RetainedEnrollmentReceipt
  ) {
    self.preparation = preparation
    self.receipt = receipt
  }
}

public struct RetainedOwnerRecoveryFailure: Codable, Equatable, Sendable {
  public let kind: RetainedOwnerRecoveryFailureKind
  public let native: RetainedEnrollmentFailure?
  public let preparation: RetainedOwnerPreparationFailure?
  public init(
    kind: RetainedOwnerRecoveryFailureKind, native: RetainedEnrollmentFailure?,
    preparation: RetainedOwnerPreparationFailure?
  ) {
    self.kind = kind
    self.native = native
    self.preparation = preparation
  }
}

public struct RetainedOwnerSettlementFailure: Codable, Equatable, Sendable {
  public let adoption: RetainedOwnerAdoptionFailure?
  public let correlation: RetainedEnrollmentFailure?
  public let end: RetainedPrivateStateFailure?
  public let kind: RetainedOwnerSettlementFailureKind
  public let preparation: RetainedOwnerPreparationFailure?
  public let reportedAdoption: RetainedOwnerAdoption?
  public let selection: RetainedOwnerRecoveryFailure?
  public init(
    adoption: RetainedOwnerAdoptionFailure?, correlation: RetainedEnrollmentFailure?,
    end: RetainedPrivateStateFailure?, kind: RetainedOwnerSettlementFailureKind,
    preparation: RetainedOwnerPreparationFailure?, reportedAdoption: RetainedOwnerAdoption?,
    selection: RetainedOwnerRecoveryFailure?
  ) {
    self.adoption = adoption
    self.correlation = correlation
    self.end = end
    self.kind = kind
    self.preparation = preparation
    self.reportedAdoption = reportedAdoption
    self.selection = selection
  }
}

public struct RetainedOwnerStatus: Codable, Equatable, Sendable {
  public let adoption: RetainedOwnerAdoption?
  public let completionCaptured: Bool
  public let purge: RetainedPurge?
  public let purgeFailure: RetainedReadFailure?
  public let recovered: RetainedOwnerRecovered?
  public let recoveryFailure: RetainedOwnerRecoveryFailure?
  public let settlementFailure: RetainedOwnerSettlementFailure?
  public let settlementKind: RetainedOwnerSettlementKind?
  public init(
    adoption: RetainedOwnerAdoption?, completionCaptured: Bool, purge: RetainedPurge?,
    purgeFailure: RetainedReadFailure?, recovered: RetainedOwnerRecovered?,
    recoveryFailure: RetainedOwnerRecoveryFailure?,
    settlementFailure: RetainedOwnerSettlementFailure?, settlementKind: RetainedOwnerSettlementKind?
  ) {
    self.adoption = adoption
    self.completionCaptured = completionCaptured
    self.purge = purge
    self.purgeFailure = purgeFailure
    self.recovered = recovered
    self.recoveryFailure = recoveryFailure
    self.settlementFailure = settlementFailure
    self.settlementKind = settlementKind
  }
}

public struct RetainedProductFailure: Codable, Equatable, Sendable {
  public let closeReason: RetainedProductCloseReason?
  public let kind: RetainedProductFailureKind
  public init(
    closeReason: RetainedProductCloseReason?, kind: RetainedProductFailureKind
  ) {
    self.closeReason = closeReason
    self.kind = kind
  }
}
