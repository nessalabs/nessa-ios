import Foundation
import NessaNative

@testable import NessaFeatures

private struct OwnerCaptureAssertion: Error { let fact: String }
private func requireOwnerFact(_ condition: Bool, _ fact: String) throws {
  guard condition else { throw OwnerCaptureAssertion(fact: fact) }
}

// Shared by the package test and actual-current-module host verification executable.
func verifyCurrentOwnerCaptures() throws {
  precondition(!Thread.isMainThread)
  let canonical = "{\"name\":\"e\u{301}\",\"epoch\":18446744073709551615}"
  let proof = FixtureNativeOwnerPhonePreparation(json: .success(canonical))
  let receipt = FixtureNativeEnrollmentReceipt(accessEpoch: UInt64.max, phase: .active)
  let recovered = FixtureNativeOwnerRecovered(preparation: proof, receipt: receipt)
  let privateFailure = FixtureNativePrivateStateFailure()
  let failedAdoption = FixtureNativeOwnerAdoptionFailure(
    acknowledgedLineage: FixtureNativePublicIntent(), phase: .publishEnrollment,
    privateState: privateFailure)
  let rejected = FixtureNativeOwnerSettlementFailure(
    adoption: failedAdoption, kind: .adoption,
    reportedAdoption: FixtureNativeOwnerAdoption())
  let owner = FixtureNativeOwnerStatus(
    adoption: nil, purge: FixtureNativePurge(), purgeFailure: .cacheUncertain,
    recovered: recovered, settlementFailure: rejected, settlementKind: nil)
  let native = FixtureNativeStatus(failure: nil, purgeFailure: nil, receipt: receipt, owner: owner)
  let captured = NativeRetainedCapture.capture(native)
  let facts = captured.owner
  try requireOwnerFact(captured.receipt?.phase == .active, "historical receipt survives")
  try requireOwnerFact(facts?.recovered?.receipt.accessEpoch == UInt64.max, "full epoch survives")
  try requireOwnerFact(
    facts?.recovered?.preparation.originalJson == .copied(Data(canonical.utf8)),
    "canonical original bytes survive")
  try requireOwnerFact(
    facts?.recovered?.preparation.deviceKey == Data(repeating: 0xa1, count: 32),
    "public device key survives")
  try requireOwnerFact(
    facts?.recovered?.preparation.requestId == Data(repeating: 0xc3, count: 16),
    "original request ID survives")
  try requireOwnerFact(
    facts?.recovered?.preparation.digest == Data(repeating: 0xb2, count: 32),
    "proof digest survives")
  try requireOwnerFact(
    facts?.recovered?.preparation.signature == Data(repeating: 0xd4, count: 64),
    "public signature survives")
  try requireOwnerFact(
    facts?.adoption == nil && facts?.settlementKind == nil,
    "refused settlement does not become success")
  try requireOwnerFact(
    facts?.settlementFailure?.adoption?.phase == .publishEnrollment,
    "actual failed phase survives")
  try requireOwnerFact(
    facts?.settlementFailure?.adoption?.acknowledgedLineage != nil,
    "independent lineage acknowledgment survives")
  try requireOwnerFact(
    facts?.settlementFailure?.reportedAdoption?.kind == .issued,
    "reported adoption survives beside rejection")
  try requireOwnerFact(
    facts?.settlementFailure?.adoption?.privateState
      == NativeRetainedCapture.capture(privateFailure), "publication cleanup payload survives")
  try requireOwnerFact(
    facts?.purge != nil && facts?.purgeFailure == .cacheUncertain,
    "purge success and later refusal remain independent")
  let persisted = try JSONDecoder().decode(
    RetainedStatus.self,
    from: JSONEncoder().encode(captured))
  try requireOwnerFact(persisted == captured, "current snapshot round trip")

  let copyRefusal = FixtureNativeOwnerPhonePreparation(
    json: .failure(.Argument(failure: .copyTooLarge)))
  let copyRecovery = NativeRetainedCapture.capture(
    FixtureNativeOwnerRecovered(
      preparation: copyRefusal, receipt: receipt))
  try requireOwnerFact(
    copyRecovery.receipt.accessEpoch == UInt64.max,
    "copy failure cannot discard remote recovery")
  try requireOwnerFact(
    copyRecovery.preparation.originalJson == .failed(.argument(.copyTooLarge)),
    "bounded copy refusal retains exact family")
  try requireOwnerFact(
    copyRecovery.preparation.signature == Data(repeating: 0xd4, count: 64),
    "copy failure retains independent proof fields")

  let selection = FixtureNativeEnrollmentFailure(kind: .otherEnrollee)
  let ownerFailure = NativeRetainedCapture.capture(
    FixtureNativeSessionFailure(
      cache: nil, enrollment: nil, kind: .owner, privateState: nil, runtimeDiagnostic: nil,
      ownerStatus: native, ownerSelection: selection))
  try requireOwnerFact(
    ownerFailure.kind == .owner && ownerFailure.ownerStatus == captured,
    "selection failure keeps whole prior status")
  try requireOwnerFact(
    ownerFailure.ownerSelection?.kind == .otherEnrollee,
    "later selection failure stays independent")
  let productFailure = NativeRetainedCapture.capture(
    FixtureNativeSessionFailure(
      cache: nil, enrollment: nil, kind: .product, privateState: nil, runtimeDiagnostic: nil,
      product: FixtureNativeProductFailure(closeReason: .credentialRevoked, kind: .authentication)))
  try requireOwnerFact(
    productFailure.product?.closeReason == .credentialRevoked,
    "typed close reason survives")
  try requireOwnerFact(
    productFailure.product?.kind == .authentication,
    "original product failure survives")
  let recursiveCopy = NativeRetainedCapture.capture(
    FixtureNativeOwnerPhonePreparation(
      json: .failure(
        .Session(
          failure: FixtureNativeSessionFailure(
            cache: nil, enrollment: nil, kind: .owner, privateState: nil, runtimeDiagnostic: nil,
            ownerStatus: native, ownerSelection: selection)))))
  guard case .failed(.session(let nested)) = recursiveCopy.originalJson else {
    throw OwnerCaptureAssertion(fact: "copy session payload is typed")
  }
  try requireOwnerFact(nested.ownerStatus == captured, "copy session retains nested owner facts")
  try requireOwnerFact(
    NativeRetainedCapture.capture(NativeReadFailure.away) == .away,
    "Away is not refusal or purge")
  try requireOwnerFact(
    NativeRetainedCapture.capture(NativeConsentClass.ownerPhoneReadWrite)
      == .ownerPhoneReadWrite, "current consent is exact")
  let readOnly = NativeRetainedCapture.capture(FixtureNativeStatus(owner: nil))
  try requireOwnerFact(readOnly.owner == nil, "current read-only scope has no owner aggregate")
}
