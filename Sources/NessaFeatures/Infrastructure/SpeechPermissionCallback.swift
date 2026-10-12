import Foundation

/// Bridges legacy permission APIs whose completion can run on an arbitrary queue.
/// The callback is explicitly Sendable and only resumes its continuation; the
/// waiting actor resumes after await before touching recording or UI state.
enum SpeechPermissionCallback {
  @MainActor static func request<Value: Sendable>(
    using start: (@escaping (Value) -> Void) -> Void
  ) async -> Value {
    await withCheckedContinuation { continuation in
      start { @Sendable value in continuation.resume(returning: value) }
    }
  }
}
