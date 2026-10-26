import Foundation
import NessaNative
import Testing

@testable import NessaFeatures

/// Compare all nested fields independently of the production capture construction.
private func fields(_ value: Any, path: String = "") -> [String: String] {
  if let value = value as? Data { return [path: "data:" + value.base64EncodedString()] }
  if let value = value as? String {
    return [path: "string:" + Data(value.utf8).base64EncodedString()]
  }
  if let value = value as? Bool { return [path: "bool:\(value)"] }
  if let value = value as? UInt64 { return [path: "u64:\(value)"] }
  let mirror = Mirror(reflecting: value)
  if mirror.displayStyle == .optional {
    guard let child = mirror.children.first else { return [path: "nil"] }
    return fields(child.value, path: path)
  }
  if mirror.displayStyle == .enum { return [path: "enum:" + String(describing: value)] }
  var result: [String: String] = [:]
  for (index, child) in mirror.children.enumerated() {
    let name = child.label?.replacingOccurrences(of: "stored_", with: "") ?? String(index)
    result.merge(fields(child.value, path: path + "." + name)) { _, new in new }
  }
  return result
}

@Test func retainedBoundaryPreservesEveryNestedPassiveFieldAndOptionalEvidence() async throws {
  await Task.detached {
    let NativeCatalogueEntry = FixtureNativeCatalogueEntry()
    #expect(
      fields(NativeRetainedCapture.capture(NativeCatalogueEntry)) == fields(NativeCatalogueEntry))
    let NativeCataloguePage = FixtureNativeCataloguePage()
    #expect(
      fields(NativeRetainedCapture.capture(NativeCataloguePage)) == fields(NativeCataloguePage))
    let NativeEnrollmentFailure = FixtureNativeEnrollmentFailure()
    #expect(
      fields(NativeRetainedCapture.capture(NativeEnrollmentFailure))
        == fields(NativeEnrollmentFailure))
    let NativeEnrollmentReceipt = FixtureNativeEnrollmentReceipt()
    #expect(
      fields(NativeRetainedCapture.capture(NativeEnrollmentReceipt))
        == fields(NativeEnrollmentReceipt))
    let NativeEntryKey = FixtureNativeEntryKey()
    #expect(fields(NativeRetainedCapture.capture(NativeEntryKey)) == fields(NativeEntryKey))
    let NativePrivateStateFailure = FixtureNativePrivateStateFailure()
    #expect(
      fields(NativeRetainedCapture.capture(NativePrivateStateFailure))
        == fields(NativePrivateStateFailure))
    let NativePublicIntent = FixtureNativePublicIntent()
    #expect(fields(NativeRetainedCapture.capture(NativePublicIntent)) == fields(NativePublicIntent))
    let NativePublicationFailure = FixtureNativePublicationFailure()
    #expect(
      fields(NativeRetainedCapture.capture(NativePublicationFailure))
        == fields(NativePublicationFailure))
    let NativePurge = FixtureNativePurge()
    #expect(fields(NativeRetainedCapture.capture(NativePurge)) == fields(NativePurge))
    let NativeRead = FixtureNativeRead()
    #expect(fields(NativeRetainedCapture.capture(NativeRead)) == fields(NativeRead))
    let NativeRefresh = FixtureNativeRefresh()
    #expect(fields(NativeRetainedCapture.capture(NativeRefresh)) == fields(NativeRefresh))
    let NativeRetry = FixtureNativeRetry()
    #expect(fields(NativeRetainedCapture.capture(NativeRetry)) == fields(NativeRetry))
    let NativeScope = FixtureNativeScope()
    #expect(fields(NativeRetainedCapture.capture(NativeScope)) == fields(NativeScope))
    let NativeSessionFailure = FixtureNativeSessionFailure()
    #expect(
      fields(NativeRetainedCapture.capture(NativeSessionFailure)) == fields(NativeSessionFailure))
    let NativeStatus = FixtureNativeStatus()
    #expect(fields(NativeRetainedCapture.capture(NativeStatus)) == fields(NativeStatus))
    let NativeWireFailure = FixtureNativeWireFailure()
    #expect(fields(NativeRetainedCapture.capture(NativeWireFailure)) == fields(NativeWireFailure))
    let empty = FixtureNativeStatus(
      completionCaptured: false, failure: nil, purge: nil, purgeAttempted: true,
      purgeFailure: .cacheDamaged, receipt: nil)
    let captured = NativeRetainedCapture.capture(empty)
    #expect(captured.completionCaptured == false)
    #expect(captured.purgeAttempted == true)
    #expect(captured.purgeFailure == .cacheDamaged)
    #expect(captured.failure == nil && captured.purge == nil && captured.receipt == nil)
  }.value
}

@Test func retainedLocalEnrollmentPreservesAllPublicFactsAndOptionalIssuedPair() async {
  await Task.detached {
    let issued = FixtureNativeLocalIssuedEnrollment()
    #expect(fields(NativeRetainedCapture.capture(issued)) == fields(issued))
    for local in [
      FixtureNativeLocalEnrollment(),
      FixtureNativeLocalEnrollment(issued: FixtureNativeLocalIssuedEnrollment()),
    ] {
      #expect(fields(NativeRetainedCapture.capture(local)) == fields(local))
    }
    let composed = "é"
    let decomposed = "e\u{301}"
    #expect(composed == decomposed)
    let value = RetainedLocalIssuedEnrollment(credential: composed, receiver: composed)
    #expect(value != .init(credential: decomposed, receiver: composed))
    #expect(value != .init(credential: composed, receiver: decomposed))
    #expect(value == .init(credential: composed, receiver: composed))
  }.value
}

@Test func retainedBoundaryPreservesEveryPinnedEnumVariant() {
  for value: NativeAttemptFailure in [
    .invalidProof, .connectionClosed, .handshakeDeadline, .verifierUnavailable,
  ] {
    #expect(NativeRetainedCapture.capture(value).rawValue == String(describing: value))
  }
  for value: NativeAttemptState in [.pending, .failed, .claimed, .superseded] {
    #expect(NativeRetainedCapture.capture(value).rawValue == String(describing: value))
  }
  for value: NativeConsentClass in [.deviceRead, .peerRead, .peerEnvironment, .ownerPhoneReadWrite]
  {
    #expect(NativeRetainedCapture.capture(value).rawValue == String(describing: value))
  }
  for value: NativeCryptoFailure in [
    .invalidCode, .invalidContext, .invalidProof, .unavailable, .pendingStorage,
  ] {
    #expect(NativeRetainedCapture.capture(value).rawValue == String(describing: value))
  }
  for value: NativeEnrollmentFailureKind in [
    .busy, .pendingExists, .enrolled, .originalNotRetryable, .noPending, .storage, .crypto,
    .handshake, .wire, .phase, .otherEnrollee, .refused, .io, .entropy, .workerFault,
  ] {
    #expect(NativeRetainedCapture.capture(value).rawValue == String(describing: value))
  }
  for value: NativeEnrollmentPhase in [
    .pending, .unclaimed, .claimed, .approved, .staging, .active, .terminal,
  ] {
    #expect(NativeRetainedCapture.capture(value).rawValue == String(describing: value))
  }
  for value: NativeKeyPublication in [.notPublished, .published] {
    #expect(NativeRetainedCapture.capture(value).rawValue == String(describing: value))
  }
  for value: NativePairingFailure in [
    .invalid, .expired, .attemptsExhausted, .capacity, .availableSlotOccupied, .conflict,
    .ineligible, .wrongActor, .staleGeneration,
  ] {
    #expect(NativeRetainedCapture.capture(value).rawValue == String(describing: value))
  }
  for value: NativePrivateStateKind in [
    .auditUnavailable, .publication, .auditPublication, .corrupt, .conflict, .locked, .unavailable,
    .uncertain,
  ] {
    #expect(NativeRetainedCapture.capture(value).rawValue == String(describing: value))
  }
  for value: NativePublicationEffect in [.notPublished, .published] {
    #expect(NativeRetainedCapture.capture(value).rawValue == String(describing: value))
  }
  for value: NativePublicationStep in [
    .validateDestination, .verifyOriginBinding, .validateReservation, .flushBeforeRename, .rename,
    .flushAfterRename, .validatePublishedDestination, .verifyPublishedBinding, .syncDirectory,
  ] {
    #expect(NativeRetainedCapture.capture(value).rawValue == String(describing: value))
  }
  for value: NativeReadFailure in [
    .refused, .unreachable, .away, .resetRequired, .`protocol`, .cache, .cacheDamaged,
    .cacheUncertain,
    .quota, .stopped, .cursorAhead, .subscriptionCapacity,
  ] {
    #expect(NativeRetainedCapture.capture(value).rawValue == String(describing: value))
  }
  for value: NativeSessionFailureKind in [
    .busy, .closed, .damaged, .runtime, .privateState, .cache, .enrollment, .noCredential, .stopped,
    .owner, .product,
  ] {
    #expect(NativeRetainedCapture.capture(value).rawValue == String(describing: value))
  }
  for value: NativeStorageFailure in [.unsafeStorage, .unavailable] {
    #expect(NativeRetainedCapture.capture(value).rawValue == String(describing: value))
  }
  for value: NativeTerminalCause in [.credentialRevoked, .denied, .cancelled, .expired, .restarted]
  {
    #expect(NativeRetainedCapture.capture(value).rawValue == String(describing: value))
  }
  for value: NativeTranscriptState in [.notLoaded, .deleted, .retained] {
    #expect(NativeRetainedCapture.capture(value).rawValue == String(describing: value))
  }
  for value: NativeWireFailureKind in [.tooLarge, .invalid, .correlation] {
    #expect(NativeRetainedCapture.capture(value).rawValue == String(describing: value))
  }
  for value: NativeWorkerFault in [.panic, .cancelled] {
    #expect(NativeRetainedCapture.capture(value).rawValue == String(describing: value))
  }
}
