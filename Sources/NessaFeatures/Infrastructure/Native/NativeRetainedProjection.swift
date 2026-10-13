import Foundation
import NessaNative

extension NativeRetainedCapture {
  static func error(_ error: Error) -> RetainedSessionError {
    if let error = error as? RetainedSessionError { return error }
    if error is CancellationError { return .cancelled }
    if let error = error as? NativeWorkerError {
      switch error {
      case .busy: return .busy
      case .closed: return .closed
      }
    }
    if let error = error as? NativeCallError {
      switch error {
      case .InvalidArgument: return .invalidArgument
      case .Session(let failure): return .session(capture(failure))
      }
    }
    if let error = error as? NativeViewError { return .view(capture(error)) }
    return .bridge
  }

  static func capture(_ error: NativeViewError) -> RetainedViewFailure {
    switch error {
    case .Busy: return .busy
    case .DamagedHandle: return .damagedHandle
    case .Cache: return .cache
    case .CacheDamaged: return .cacheDamaged
    case .CacheUncertain: return .cacheUncertain
    case .ResetRequired: return .resetRequired
    case .Quota: return .quota
    case .InvalidTarget: return .invalidTarget
    case .ViewTooLarge: return .viewTooLarge
    case .Serialization: return .serialization
    }
  }

  static func transcript(
    _ value: any NativeTranscriptProtocol, conversation: String, revision: UUID
  ) -> RetainedTranscript {
    let state = capture(value.state())
    let scope = value.scope().map { capture($0) }
    let downloaded = value.downloaded()
    let applied = value.applied()
    let facts = value.facts()
    let generation = value.generation()
    let view: RetainedViewOutcome
    do {
      if let json = try value.viewJson() {
        view = projection(Data(json.utf8), conversation: conversation, revision: revision)
      } else {
        view = .absent
      }
    } catch let error as NativeViewError {
      view = .failed(.init(failure: .native(capture(error)), json: nil))
    } catch {
      view = .failed(.init(failure: .bridge, json: nil))
    }
    return RetainedTranscript(
      state: state, scope: scope, downloaded: downloaded, applied: applied, facts: facts,
      generation: generation, view: view)
  }

  private struct Identity: Decodable {
    let conversationId: String
    let revision: String
  }

  private static func projection(
    _ json: Data, conversation: String, revision: UUID
  ) -> RetainedViewOutcome {
    do {
      let identity = try JSONDecoder().decode(Identity.self, from: json)
      // Projection owns the full "epoch:counter[:suffix]" display revision.
      // Only correlate its injected epoch; do not reinterpret it as saved progress.
      guard identity.conversationId.utf8.elementsEqual(conversation.utf8),
        identity.revision.hasPrefix(revision.uuidString.lowercased() + ":")
      else {
        return .failed(.init(failure: .targetMismatch, json: json))
      }
      let display = try JSONDecoder().decode(NessaConversationView.self, from: json)
      return .available(
        .init(json: json, revision: identity.revision, revisionEpoch: revision, display: display))
    } catch {
      return .failed(.init(failure: .invalidDocument, json: json))
    }
  }
}
