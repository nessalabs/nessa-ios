import Foundation
import NessaNative
import Testing

@testable import NessaFeatures

private let revision = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
private let completeJSON = """
  {"conversationId":"conversation", "revision":"00000000-0000-4000-8000-000000000001:18446744073709551615:ui:ff",
   "messages":[],"permissions":[],"truncated":false,"pending":[{"opaque":18446744073709551615}],
   "questions":[],"tools":[],"capabilities":{"opaque":null},"lifecycle":{"phase":"attached"},
   "queueComplete":true,"transcriptState":"complete_empty","title":null,"lease":{"opaque":"lease"},
   "artifacts":[{"opaque":"artifact"}],"futureField":{"value":18446744073709551615}}
  """

@Test func retainedProjectionKeepsCompleteBytesAndFailureDoesNotErasePhysicalEvidence() async throws
{
  await Task.detached {
    let snapshot = FixtureNativeTranscript(json: .success(completeJSON))
    let captured = NativeRetainedCapture.transcript(
      snapshot, conversation: "conversation", revision: revision)
    #expect(captured.state == .retained)
    #expect(captured.downloaded == UInt64.max - 1)
    #expect(captured.applied == UInt64.max)
    guard case .available(let projection) = captured.view else {
      Issue.record("valid full native payload was lost")
      return
    }
    #expect(projection.json == Data(completeJSON.utf8))
    #expect(projection.display.conversationId == "conversation")
    #expect(projection.revisionEpoch == revision)
    #expect(
      projection.revision == "00000000-0000-4000-8000-000000000001:18446744073709551615:ui:ff")
    for (json, failure) in [
      (
        completeJSON.replacingOccurrences(
          of: "conversationId\":\"conversation", with: "conversationId\":\"foreign"),
        RetainedProjectionFailure.targetMismatch
      ),
      (completeJSON.replacingOccurrences(of: "4000", with: "4001"), .targetMismatch),
      (
        completeJSON.replacingOccurrences(of: "\"messages\":[]", with: "\"messages\":null"),
        .invalidDocument
      ),
      ("{", .invalidDocument),
    ] {
      let invalid = NativeRetainedCapture.transcript(
        FixtureNativeTranscript(json: .success(json)), conversation: "conversation",
        revision: revision)
      #expect(invalid.state == captured.state && invalid.scope == captured.scope)
      #expect(invalid.downloaded == captured.downloaded && invalid.applied == captured.applied)
      #expect(invalid.facts == captured.facts && invalid.generation == captured.generation)
      #expect(invalid.view == .failed(.init(failure: failure, json: Data(json.utf8))))
    }
    let failed = NativeRetainedCapture.transcript(
      FixtureNativeTranscript(json: .failure(.ViewTooLarge)), conversation: "conversation",
      revision: revision)
    #expect(failed.view == .failed(.init(failure: .native(.viewTooLarge), json: nil)))
    #expect(failed.scope == captured.scope && failed.downloaded == captured.downloaded)
  }.value
}

@Test func retainedRetryKeepsDifferentAttemptAndNestedFailureCategories() async throws {
  await Task.detached {
    let original = FixtureNativeEnrollmentReceipt()
    let retry = FixtureNativeEnrollmentReceipt(
      publicIntent: FixtureNativePublicIntent(attempt: Data(repeating: 9, count: 16)))
    let value = NativeRetainedCapture.capture(
      FixtureNativeRetry(original: original, retried: retry))
    #expect(!value.original.sameIntent(as: value.retried))
    #expect(value.original.sameIntent(as: value.original))
    #expect(value.original.publicIntent.invitation == value.retried.publicIntent.invitation)
    #expect(value.original.publicIntent.expiryMs == UInt64.max - 3)
    let native = FixtureNativeSessionFailure()
    #expect(
      NativeRetainedCapture.error(NativeCallError.Session(failure: native))
        == .session(NativeRetainedCapture.capture(native)))
    #expect(NativeRetainedCapture.error(NativeCallError.InvalidArgument) == .invalidArgument)
    #expect(NativeRetainedCapture.error(NativeViewError.CacheDamaged) == .view(.cacheDamaged))
    #expect(NativeRetainedCapture.error(NativeWorkerError.busy) == .busy)
    #expect(NativeRetainedCapture.error(NativeWorkerError.closed) == .closed)
    #expect(NativeRetainedCapture.error(CancellationError()) == .cancelled)
    #expect(NativeRetainedCapture.error(NSError(domain: "foreign", code: 1)) == .bridge)
  }.value
}

@Test @MainActor func realRetainedApplicationFactoryOpensCapturesClosesAndReopens() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    .resolvingSymlinksInPath()
  try FileManager.default.createDirectory(
    at: root.appendingPathComponent("session"), withIntermediateDirectories: true,
    attributes: [.posixPermissions: 0o700])
  defer { try? FileManager.default.removeItem(at: root) }
  let location = RetainedSessionLocation(
    root: root.path, directory: "session", address: "127.0.0.1:9")
  let factory: any RetainedSessionFactory = NativeRetainedSessionFactory()
  let session = try await factory.open(location)
  #expect(try await session.localEnrollment() == nil)
  let status = try await session.status()
  #expect(!status.completionCaptured && status.failure?.kind == .io && !status.purgeAttempted)
  #expect(status.receipt == nil && status.purge == nil && status.purgeFailure == nil)
  await #expect(
    throws: RetainedSessionError.session(
      .init(
        cache: nil, enrollment: nil, kind: .noCredential, privateState: nil, runtimeDiagnostic: nil)
    )
  ) {
    try await session.cataloguePage(after: nil, maximum: 16)
  }
  await #expect(throws: RetainedSessionError.invalidArgument) {
    try await session.cataloguePage(after: .init(creation: UInt64.max, id: " "), maximum: 16)
  }
  // The owner's physical drain remains mandatory even when its caller is cancelled.
  let close = Task { try await session.close() }
  close.cancel()
  try await close.value
  await #expect(throws: RetainedSessionError.closed) { try await session.status() }
  await #expect(throws: RetainedSessionError.closed) { try await session.localEnrollment() }
  let reopened = try await factory.open(location)
  #expect(try await reopened.localEnrollment() == nil)
  try await reopened.close()
  let files = try FileManager.default.contentsOfDirectory(
    atPath: root.appendingPathComponent("session").path)
  #expect(!files.isEmpty)
}

@Test @MainActor func nativeFactoryUsesExplicitSelectorsAndIsOnlyComposedInLiveMode() async throws {
  #expect(NessaDependencies.live().retainedSessions is NativeRetainedSessionFactory)
  #expect(NessaDependencies.development().retainedSessions == nil)
  let location = RetainedSessionLocation(
    root: "/", directory: "../", address: "hostname.example:123")
  await #expect(throws: RetainedSessionError.invalidArgument) {
    try await NativeRetainedSessionFactory().open(location)
  }
}
