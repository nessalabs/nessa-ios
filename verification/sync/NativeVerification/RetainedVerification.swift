import Foundation
import NessaFeatures

/// Runs inside the existing disposable paired-gateway lifecycle fixture.
enum RetainedVerification {
  enum Failure: Error { case assertion(String) }
  static func require(_ value: Bool, _ message: String) throws {
    if !value { throw Failure.assertion(message) }
  }
  static func run(_ arguments: [String]) async throws {
    let mode = arguments[0]
    let location = RetainedSessionLocation(
      root: arguments[1], directory: arguments[2], address: arguments[3])
    let conversation = arguments[4]
    let receiver = arguments[5]
    let origin = arguments[6]
    let revision = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    let factory: any RetainedSessionFactory = NativeRetainedSessionFactory()
    let session = try await factory.open(location)
    do {
      if mode != "offline" {
        let refresh = try await session.refresh()
        let status = refresh.initial
        try require(status.completionCaptured, "missing physical completion")
        if mode == "terminal" {
          try require(status.receipt?.phase == .terminal, "lost terminal receipt")
          try require(status.receipt?.terminalCause == .credentialRevoked, "lost revocation cause")
          try require(
            status.purgeAttempted && status.purgeFailure == nil, "lost independent purge outcome")
          guard let purge = status.purge else { throw Failure.assertion("missing purge") }
          try require(
            purge.receiver == receiver && purge.records > 0 && purge.transcripts > 0,
            "lost purge evidence")
          let recovered = try await session.purgeReceipt(receiver: receiver)
          try require(recovered == purge, "historical purge changed")
          try require(
            refresh.read == nil && refresh.recheck == nil, "terminal refresh fabricated read")
          do {
            _ = try await session.transcript(conversation: conversation, revision: revision)
            throw Failure.assertion("purged session admitted saved history")
          } catch RetainedSessionError.session(let failure) {
            try require(failure.kind == .noCredential, "wrong terminal read refusal")
          }
          try await session.close()
          let reopened = try await factory.open(location)
          let persisted = try await reopened.purgeReceipt(receiver: receiver)
          try require(persisted == recovered, "restart lost historical purge receipt")
          try await reopened.close()
          print("PASS: application terminal capture, typed refusal and durable purge recovery")
          return
        }
        try require(
          status.receipt?.phase == .active && !status.purgeAttempted, "lost active receipt")
        try require(
          status.receipt?.receiver == receiver && status.failure == nil, "foreign active receiver")
        guard let intent = status.receipt?.publicIntent else {
          throw Failure.assertion("missing intent")
        }
        try require(
          intent.invitation.count == 16 && intent.attempt.count == 16 && intent.consent.count == 16,
          "correlation lost")
        try require(intent.consentClass == .deviceRead && intent.generation > 0, "intent changed")
        try require(refresh.selectionFailure == nil, "unexpected selection failure")
        if mode == "epoch" {
          try require(refresh.read?.failure == .refused, "missing read refusal")
          try require(refresh.recheck?.failure?.kind == .refused, "lost pinned recheck")
          try require(
            refresh.recheck?.receipt == nil && refresh.recheck?.purgeAttempted == false,
            "generic refusal became purge")
          let purge = try await session.purgeReceipt(receiver: receiver)
          try require(purge == nil, "generic refusal generated purge receipt")
        } else {
          try require(
            refresh.read?.complete == true && refresh.read?.failure == nil, "read did not complete")
          try require(
            refresh.read?.withdrawn.isEmpty == true && refresh.recheck == nil,
            "unexpected withdrawals/recheck")
          if mode == "resumed" {
            try require(refresh.read?.moved == false, "restart redownloaded retained progress")
          }
        }
      }
      guard let page = try await session.cataloguePage(after: nil, maximum: 16) else {
        throw Failure.assertion("missing retained catalogue")
      }
      try require(page.scope.receiver == receiver && page.scope.origin == origin, "scope changed")
      try require(page.generation > 0 && page.entries.count >= 2, "catalogue progress lost")
      guard let first = page.entries.first else { throw Failure.assertion("empty catalogue") }
      let next = try await session.cataloguePage(after: first.key, maximum: 16)
      try require(
        next?.entries.contains { $0.key == first.key } == false, "cursor was not restored")
      let transcript = try await session.transcript(conversation: conversation, revision: revision)
      // Catalogue and transcript select different physical streams. Preserve each scope.
      try require(
        transcript.state == .retained && transcript.scope?.receiver == receiver
          && transcript.scope?.origin == origin, "retained transcript scope lost")
      try require(
        transcript.scope?.stream != page.scope.stream, "catalogue stream substituted for transcript"
      )
      try require(
        (transcript.downloaded ?? 0) > 0 && (transcript.generation ?? 0) > 0,
        "physical progress lost")
      if mode == "epoch" {
        try require(
          transcript.downloaded! > transcript.applied!, "partial progress falsely applied")
        try require(
          transcript.facts! <= transcript.applied!, "fact progress advanced independently")
      } else {
        try require(transcript.downloaded == transcript.applied, "completed progress mismatched")
      }
      guard case .available(let view) = transcript.view else {
        if case .failed(let capture) = transcript.view {
          print("View failure: \(capture.failure)")
          if let json = capture.json {
            struct Root: Decodable {
              let revision: String
              let conversationId: String
            }
            do { print("Root: \(try JSONDecoder().decode(Root.self, from: json))") } catch {
              print("Root decoding failed: \(error)")
            }
            do { _ = try JSONDecoder().decode(NessaConversationView.self, from: json) } catch {
              print("Display decoding failed: \(error)")
            }
          }
        }
        throw Failure.assertion("full native view unavailable")
      }
      try require(
        view.display.conversationId == conversation && view.revisionEpoch == revision,
        "view target mismatch")
      try await session.close()
      do {
        _ = try await session.status()
        throw Failure.assertion("closed session admitted status")
      } catch RetainedSessionError.closed {}
      let reopened = try await factory.open(location)
      let saved = try await reopened.transcript(conversation: conversation, revision: revision)
      try require(
        saved.scope == transcript.scope && saved.downloaded == transcript.downloaded
          && saved.applied == transcript.applied, "offline reopen changed physical evidence")
      guard case .available(let savedView) = saved.view else {
        throw Failure.assertion("reopen lost view")
      }
      if mode != "epoch" { try require(savedView.json == view.json, "reopen changed full bytes") }
      try await reopened.close()
      print(
        "PASS: application \(mode) paired scope, progress, full payload, cursor and close/reopen")
    } catch {
      try? await session.close()
      throw error
    }
  }
}

/// Normal imports must support application-port replacement without native handles.
private struct RetainedFactorySubstitute: RetainedSessionFactory {
  func open(_ location: RetainedSessionLocation) async throws -> any RetainedSession {
    RetainedSessionSubstitute()
  }
}
private struct RetainedSessionSubstitute: RetainedSession {
  func enroll(code: String) async throws -> RetainedEnrollmentReceipt {
    throw RetainedSessionError.cancelled
  }
  func retry(code: String) async throws -> RetainedRetry { throw RetainedSessionError.cancelled }
  func status() async throws -> RetainedStatus {
    .init(
      completionCaptured: false, failure: nil, purge: nil, purgeAttempted: false, purgeFailure: nil,
      receipt: nil)
  }
  func refresh() async throws -> RetainedRefresh {
    .init(initial: try await status(), read: nil, recheck: nil, selectionFailure: nil)
  }
  func cataloguePage(after: RetainedEntryKey?, maximum: UInt32) async throws
    -> RetainedCataloguePage?
  { nil }
  func transcript(conversation: String, revision: UUID) async throws -> RetainedTranscript {
    .init(
      state: .notLoaded, scope: nil, downloaded: nil, applied: nil, facts: nil, generation: nil,
      view: .absent)
  }
  func purgeReceipt(receiver: String) async throws -> RetainedPurge? { nil }
  func close() async throws {}
}
