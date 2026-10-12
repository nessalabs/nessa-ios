import Combine
import Foundation

@MainActor public final class DictationViewModel: ObservableObject {
  public enum State { case idle, requesting, listening, finishing }
  @Published public private(set) var state: State = .idle
  @Published public private(set) var transcript = ""
  @Published public private(set) var transcriptRevision = UUID()
  @Published public var error: String?
  public var active: Bool { state != .idle }
  private let transcriber: any SpeechTranscribing
  private var task: Task<Void, Never>?
  private var token = UUID()
  public init(transcriber: any SpeechTranscribing) { self.transcriber = transcriber }

  public func toggle() {
    if state == .listening {
      state = .finishing
      transcriber.finish()
    } else if state == .idle {
      start()
    } else if state == .requesting {
      cancel()
    }
  }
  public func start() {
    guard state == .idle else { return }
    transcript = ""
    error = nil
    token = UUID()
    let expected = token
    state = .requesting
    task = Task { [weak self] in
      guard let self else { return }
      defer {
        if token == expected {
          state = .idle
          task = nil
        }
      }
      do {
        let stream = try await transcriber.start()
        guard token == expected, !Task.isCancelled else { return }
        state = .listening
        var finalized = false
        for try await result in stream {
          guard token == expected, !Task.isCancelled else { return }
          transcript = result.text
          transcriptRevision = UUID()
          finalized = finalized || result.isFinal
        }
        if !finalized, token == expected, !Task.isCancelled { throw DictationError.incomplete }
      } catch {
        if token == expected, !Task.isCancelled { self.error = error.localizedDescription }
      }
    }
  }
  public func cancel() {
    token = UUID()
    task?.cancel()
    task = nil
    transcriber.cancel()
    state = .idle
  }
}
