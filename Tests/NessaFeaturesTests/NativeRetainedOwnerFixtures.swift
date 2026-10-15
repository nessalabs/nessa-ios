import Foundation
import NessaNative

// Never lowered into Rust; every getter verifies the off-UI capture boundary.
final class FixtureNativeOwnerAdoption: NativeOwnerAdoption, @unchecked Sendable {
  let stored_kind: NativeOwnerEnrollmentKind
  let stored_publicIntent: NativePublicIntent
  init(
    kind: NativeOwnerEnrollmentKind = .issued,
    publicIntent: NativePublicIntent = FixtureNativePublicIntent()
  ) {
    stored_kind = kind
    stored_publicIntent = publicIntent
    super.init(noHandle: .init())
  }
  required init(unsafeFromHandle handle: UInt64) { fatalError("fixture cannot be lowered") }
  override func kind() -> NativeOwnerEnrollmentKind {
    precondition(!Thread.isMainThread)
    return stored_kind
  }
  override func publicIntent() -> NativePublicIntent {
    precondition(!Thread.isMainThread)
    return stored_publicIntent
  }
}

final class FixtureNativeOwnerAdoptionFailure: NativeOwnerAdoptionFailure, @unchecked Sendable {
  let stored_acknowledgedLineage: NativePublicIntent?
  let stored_phase: NativeOwnerAdoptionPhase
  let stored_privateState: NativePrivateStateFailure
  init(
    acknowledgedLineage: NativePublicIntent? = nil,
    phase: NativeOwnerAdoptionPhase = .publishEnrollment,
    privateState: NativePrivateStateFailure = FixtureNativePrivateStateFailure()
  ) {
    stored_acknowledgedLineage = acknowledgedLineage
    stored_phase = phase
    stored_privateState = privateState
    super.init(noHandle: .init())
  }
  required init(unsafeFromHandle handle: UInt64) { fatalError("fixture cannot be lowered") }
  override func acknowledgedLineage() -> NativePublicIntent? {
    precondition(!Thread.isMainThread)
    return stored_acknowledgedLineage
  }
  override func phase() -> NativeOwnerAdoptionPhase {
    precondition(!Thread.isMainThread)
    return stored_phase
  }
  override func privateState() -> NativePrivateStateFailure {
    precondition(!Thread.isMainThread)
    return stored_privateState
  }
}

final class FixtureNativeOwnerPhonePreparation: NativeOwnerPhonePreparation, @unchecked Sendable {
  let stored_deviceKey: Data
  let stored_digest: Data
  let stored_requestId: Data
  let stored_signature: Data
  let json: Result<String, NativeOwnerPreparationCallError>
  init(
    deviceKey: Data = Data(repeating: 0xa1, count: 32),
    digest: Data = Data(repeating: 0xb2, count: 32),
    requestId: Data = Data(repeating: 0xc3, count: 16),
    signature: Data = Data(repeating: 0xd4, count: 64),
    json: Result<String, NativeOwnerPreparationCallError> = .success(
      "{\"original\":\"public-proof\"}")
  ) {
    stored_deviceKey = deviceKey
    stored_digest = digest
    stored_requestId = requestId
    stored_signature = signature
    self.json = json
    super.init(noHandle: .init())
  }
  required init(unsafeFromHandle handle: UInt64) { fatalError("fixture cannot be lowered") }
  override func deviceKey() -> Data {
    precondition(!Thread.isMainThread)
    return stored_deviceKey
  }
  override func digest() -> Data {
    precondition(!Thread.isMainThread)
    return stored_digest
  }
  override func originalJson() throws -> String {
    precondition(!Thread.isMainThread)
    return try json.get()
  }
  override func requestId() -> Data {
    precondition(!Thread.isMainThread)
    return stored_requestId
  }
  override func signature() -> Data {
    precondition(!Thread.isMainThread)
    return stored_signature
  }
}

final class FixtureNativeOwnerPreparationFailure: NativeOwnerPreparationFailure, @unchecked Sendable
{
  let stored_crypto: NativeCryptoFailure?
  let stored_kind: NativeOwnerPreparationFailureKind
  let stored_privateState: NativePrivateStateFailure?
  init(
    crypto: NativeCryptoFailure? = nil,
    kind: NativeOwnerPreparationFailureKind = .private,
    privateState: NativePrivateStateFailure? = nil
  ) {
    stored_crypto = crypto
    stored_kind = kind
    stored_privateState = privateState
    super.init(noHandle: .init())
  }
  required init(unsafeFromHandle handle: UInt64) { fatalError("fixture cannot be lowered") }
  override func crypto() -> NativeCryptoFailure? {
    precondition(!Thread.isMainThread)
    return stored_crypto
  }
  override func kind() -> NativeOwnerPreparationFailureKind {
    precondition(!Thread.isMainThread)
    return stored_kind
  }
  override func privateState() -> NativePrivateStateFailure? {
    precondition(!Thread.isMainThread)
    return stored_privateState
  }
}

final class FixtureNativeOwnerRecovered: NativeOwnerRecovered, @unchecked Sendable {
  let stored_preparation: NativeOwnerPhonePreparation
  let stored_receipt: NativeEnrollmentReceipt
  init(
    preparation: NativeOwnerPhonePreparation = FixtureNativeOwnerPhonePreparation(),
    receipt: NativeEnrollmentReceipt = FixtureNativeEnrollmentReceipt()
  ) {
    stored_preparation = preparation
    stored_receipt = receipt
    super.init(noHandle: .init())
  }
  required init(unsafeFromHandle handle: UInt64) { fatalError("fixture cannot be lowered") }
  override func preparation() -> NativeOwnerPhonePreparation {
    precondition(!Thread.isMainThread)
    return stored_preparation
  }
  override func receipt() -> NativeEnrollmentReceipt {
    precondition(!Thread.isMainThread)
    return stored_receipt
  }
}

final class FixtureNativeOwnerRecoveryFailure: NativeOwnerRecoveryFailure, @unchecked Sendable {
  let stored_kind: NativeOwnerRecoveryFailureKind
  let stored_native: NativeEnrollmentFailure?
  let stored_preparation: NativeOwnerPreparationFailure?
  init(
    kind: NativeOwnerRecoveryFailureKind = .native,
    native: NativeEnrollmentFailure? = nil,
    preparation: NativeOwnerPreparationFailure? = nil
  ) {
    stored_kind = kind
    stored_native = native
    stored_preparation = preparation
    super.init(noHandle: .init())
  }
  required init(unsafeFromHandle handle: UInt64) { fatalError("fixture cannot be lowered") }
  override func kind() -> NativeOwnerRecoveryFailureKind {
    precondition(!Thread.isMainThread)
    return stored_kind
  }
  override func native() -> NativeEnrollmentFailure? {
    precondition(!Thread.isMainThread)
    return stored_native
  }
  override func preparation() -> NativeOwnerPreparationFailure? {
    precondition(!Thread.isMainThread)
    return stored_preparation
  }
}

final class FixtureNativeOwnerSettlementFailure: NativeOwnerSettlementFailure, @unchecked Sendable {
  let stored_adoption: NativeOwnerAdoptionFailure?
  let stored_correlation: NativeEnrollmentFailure?
  let stored_end: NativePrivateStateFailure?
  let stored_kind: NativeOwnerSettlementFailureKind
  let stored_preparation: NativeOwnerPreparationFailure?
  let stored_reportedAdoption: NativeOwnerAdoption?
  let stored_selection: NativeOwnerRecoveryFailure?
  init(
    adoption: NativeOwnerAdoptionFailure? = nil,
    correlation: NativeEnrollmentFailure? = nil,
    end: NativePrivateStateFailure? = nil,
    kind: NativeOwnerSettlementFailureKind = .adoption,
    preparation: NativeOwnerPreparationFailure? = nil,
    reportedAdoption: NativeOwnerAdoption? = nil,
    selection: NativeOwnerRecoveryFailure? = nil
  ) {
    stored_adoption = adoption
    stored_correlation = correlation
    stored_end = end
    stored_kind = kind
    stored_preparation = preparation
    stored_reportedAdoption = reportedAdoption
    stored_selection = selection
    super.init(noHandle: .init())
  }
  required init(unsafeFromHandle handle: UInt64) { fatalError("fixture cannot be lowered") }
  override func adoption() -> NativeOwnerAdoptionFailure? {
    precondition(!Thread.isMainThread)
    return stored_adoption
  }
  override func correlation() -> NativeEnrollmentFailure? {
    precondition(!Thread.isMainThread)
    return stored_correlation
  }
  override func end() -> NativePrivateStateFailure? {
    precondition(!Thread.isMainThread)
    return stored_end
  }
  override func kind() -> NativeOwnerSettlementFailureKind {
    precondition(!Thread.isMainThread)
    return stored_kind
  }
  override func preparation() -> NativeOwnerPreparationFailure? {
    precondition(!Thread.isMainThread)
    return stored_preparation
  }
  override func reportedAdoption() -> NativeOwnerAdoption? {
    precondition(!Thread.isMainThread)
    return stored_reportedAdoption
  }
  override func selection() -> NativeOwnerRecoveryFailure? {
    precondition(!Thread.isMainThread)
    return stored_selection
  }
}

final class FixtureNativeOwnerStatus: NativeOwnerStatus, @unchecked Sendable {
  let stored_adoption: NativeOwnerAdoption?
  let stored_completionCaptured: Bool
  let stored_purge: NativePurge?
  let stored_purgeFailure: NativeReadFailure?
  let stored_recovered: NativeOwnerRecovered?
  let stored_recoveryFailure: NativeOwnerRecoveryFailure?
  let stored_settlementFailure: NativeOwnerSettlementFailure?
  let stored_settlementKind: NativeOwnerSettlementKind?
  init(
    adoption: NativeOwnerAdoption? = nil,
    completionCaptured: Bool = true,
    purge: NativePurge? = nil,
    purgeFailure: NativeReadFailure? = nil,
    recovered: NativeOwnerRecovered? = nil,
    recoveryFailure: NativeOwnerRecoveryFailure? = nil,
    settlementFailure: NativeOwnerSettlementFailure? = nil,
    settlementKind: NativeOwnerSettlementKind? = .adopted
  ) {
    stored_adoption = adoption
    stored_completionCaptured = completionCaptured
    stored_purge = purge
    stored_purgeFailure = purgeFailure
    stored_recovered = recovered
    stored_recoveryFailure = recoveryFailure
    stored_settlementFailure = settlementFailure
    stored_settlementKind = settlementKind
    super.init(noHandle: .init())
  }
  required init(unsafeFromHandle handle: UInt64) { fatalError("fixture cannot be lowered") }
  override func adoption() -> NativeOwnerAdoption? {
    precondition(!Thread.isMainThread)
    return stored_adoption
  }
  override func completionCaptured() -> Bool {
    precondition(!Thread.isMainThread)
    return stored_completionCaptured
  }
  override func purge() -> NativePurge? {
    precondition(!Thread.isMainThread)
    return stored_purge
  }
  override func purgeFailure() -> NativeReadFailure? {
    precondition(!Thread.isMainThread)
    return stored_purgeFailure
  }
  override func recovered() -> NativeOwnerRecovered? {
    precondition(!Thread.isMainThread)
    return stored_recovered
  }
  override func recoveryFailure() -> NativeOwnerRecoveryFailure? {
    precondition(!Thread.isMainThread)
    return stored_recoveryFailure
  }
  override func settlementFailure() -> NativeOwnerSettlementFailure? {
    precondition(!Thread.isMainThread)
    return stored_settlementFailure
  }
  override func settlementKind() -> NativeOwnerSettlementKind? {
    precondition(!Thread.isMainThread)
    return stored_settlementKind
  }
}

final class FixtureNativeProductFailure: NativeProductFailure, @unchecked Sendable {
  let stored_closeReason: NativeProductCloseReason?
  let stored_kind: NativeProductFailureKind
  init(
    closeReason: NativeProductCloseReason? = .credentialRevoked,
    kind: NativeProductFailureKind = .authentication
  ) {
    stored_closeReason = closeReason
    stored_kind = kind
    super.init(noHandle: .init())
  }
  required init(unsafeFromHandle handle: UInt64) { fatalError("fixture cannot be lowered") }
  override func closeReason() -> NativeProductCloseReason? {
    precondition(!Thread.isMainThread)
    return stored_closeReason
  }
  override func kind() -> NativeProductFailureKind {
    precondition(!Thread.isMainThread)
    return stored_kind
  }
}
