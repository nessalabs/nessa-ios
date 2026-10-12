import Foundation

@MainActor public final class MockSpeechTranscriber: SpeechTranscribing {
  public init() {}
  public func start() async throws -> AsyncThrowingStream<SpeechTranscript, Error> {
    AsyncThrowingStream { continuation in
      continuation.yield(SpeechTranscript(text: "This is a mocked voice message.", isFinal: true))
      continuation.finish()
    }
  }
  public func finish() {}
  public func cancel() {}
}
