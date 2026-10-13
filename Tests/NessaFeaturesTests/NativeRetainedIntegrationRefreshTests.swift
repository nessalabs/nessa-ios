import Foundation
import NessaNative
import Testing

@testable import NessaFeatures

@Test func nativeUncertainCacheKeepsIndependentCompletionAndSelectionEvidence() async {
  await Task.detached {
    let read = NativeRetainedCapture.capture(FixtureNativeRead(failure: .cacheUncertain))
    #expect(read.failure == .cacheUncertain && read.complete == true && read.moved == true)
    #expect(read.conversations == UInt64.max - 1)
    #expect(read.withdrawn == [" withdrawn-a ", "withdrawn-b"])
    let failure = NativeRetainedCapture.error(
      NativeCallError.Session(failure: FixtureNativeSessionFailure(cache: .cacheUncertain)))
    guard case .session(let session) = failure else {
      Issue.record("session failure category lost")
      return
    }
    #expect(session.cache == .cacheUncertain && session.privateState != nil)
    let status = NativeRetainedCapture.capture(FixtureNativeStatus(purgeFailure: .cacheUncertain))
    #expect(status.purgeFailure == .cacheUncertain && status.completionCaptured)
    #expect(status.receipt != nil && status.purge != nil && status.failure != nil)
    #expect(NativeRetainedCapture.error(NativeViewError.CacheUncertain) == .view(.cacheUncertain))
    let transcript = NativeRetainedCapture.transcript(
      FixtureNativeTranscript(json: .failure(.CacheUncertain)), conversation: "conversation",
      revision: UUID())
    #expect(transcript.view == .failed(.init(failure: .native(.cacheUncertain), json: nil)))
    #expect(transcript.state == .retained && transcript.applied == UInt64.max)
    #expect(transcript.downloaded == UInt64.max - 1 && transcript.scope != nil)
    #expect(RetainedReadFailure.cacheUncertain != .cache)
    #expect(RetainedReadFailure.cacheUncertain != .cacheDamaged)
  }.value
}

@Test func nativeIntentWireNameSurvivesAllClassesAndPhasesWithoutLocalDerivation() async {
  await Task.detached {
    let classes: [(NativeConsentClass, String)] = [
      (.deviceRead, "gateway-conversation-read"),
      (.peerRead, "peer-gateway-conversation-read"),
      (.peerEnvironment, "peer-gateway-environment-serve"),
    ]
    let phases: [NativeEnrollmentPhase] = [
      .pending, .unclaimed, .claimed, .approved, .staging, .active, .terminal,
    ]
    for (consentClass, name) in classes {
      for phase in phases {
        let intent = FixtureNativePublicIntent(consentClass: consentClass, consentClassName: name)
        let receipt = NativeRetainedCapture.capture(
          FixtureNativeEnrollmentReceipt(phase: phase, publicIntent: intent))
        #expect(receipt.publicIntent.consentClassName.utf8.elementsEqual(name.utf8))
        #expect(receipt.phase.rawValue == String(describing: phase))
        let local = NativeRetainedCapture.capture(
          FixtureNativeLocalEnrollment(publicIntent: intent))
        #expect(local.publicIntent == receipt.publicIntent)
      }
    }
    // Passive capture must preserve a published name even when a substitute changes it.
    let unusual = NativeRetainedCapture.capture(
      FixtureNativePublicIntent(consentClass: .deviceRead, consentClassName: "owner-published-name")
    )
    #expect(unusual.consentClassName == "owner-published-name")
    let composed = NativeRetainedCapture.capture(FixtureNativePublicIntent(consentClassName: "é"))
    let decomposed = NativeRetainedCapture.capture(
      FixtureNativePublicIntent(consentClassName: "e\u{301}"))
    #expect(composed.consentClassName == decomposed.consentClassName)
    #expect(composed != decomposed)
    for changed in [
      FixtureNativePublicIntent(attempt: Data(), consentClassName: "é"),
      FixtureNativePublicIntent(consent: Data(), consentClassName: "é"),
      FixtureNativePublicIntent(consentClass: .deviceRead, consentClassName: "é"),
      FixtureNativePublicIntent(consentClassName: "é", expiryMs: 0),
      FixtureNativePublicIntent(consentClassName: "é", generation: 0),
      FixtureNativePublicIntent(consentClassName: "é", invitation: Data()),
    ] {
      #expect(composed != NativeRetainedCapture.capture(changed))
    }
    let original = FixtureNativeEnrollmentReceipt(
      publicIntent: FixtureNativePublicIntent(consentClassName: "é"))
    let changed = FixtureNativeEnrollmentReceipt(
      publicIntent: FixtureNativePublicIntent(consentClassName: "e\u{301}"))
    #expect(
      !NativeRetainedCapture.capture(original).sameIntent(
        as: NativeRetainedCapture.capture(changed)))
  }.value
}
