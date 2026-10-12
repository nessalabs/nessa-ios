import Foundation

public struct SpeechTranscript: Equatable, Sendable {
  public let text: String
  public let isFinal: Bool
  public init(text: String, isFinal: Bool) {
    self.text = text
    self.isFinal = isFinal
  }
}

@MainActor public protocol SpeechTranscribing: AnyObject {
  func start() async throws -> AsyncThrowingStream<SpeechTranscript, Error>
  func finish()
  func cancel()
}

public enum DictationError: Error, LocalizedError {
  case speechPermission, microphonePermission, unavailable, failed, incomplete
  public var errorDescription: String? {
    switch self {
    case .speechPermission: "Allow speech recognition for Nessa in Settings."
    case .microphonePermission: "Allow microphone access for Nessa in Settings."
    case .unavailable: "Dictation is unavailable on this device or for this language."
    case .failed: "Dictation failed. Please try again."
    case .incomplete: "Dictation couldn’t finish. Check the text before sending."
    }
  }
}
