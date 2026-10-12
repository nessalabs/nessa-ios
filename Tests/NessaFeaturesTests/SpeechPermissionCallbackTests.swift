import Foundation
import Testing

@testable import NessaFeatures

// Models an Objective-C completion API that omits its Sendable annotation. The
// box is a test-only bridge to dispatch; production receives a Sendable relay.
private final class LegacyPermissionBlock: @unchecked Sendable {
  private let completion: (Bool) -> Void
  init(_ completion: @escaping (Bool) -> Void) { self.completion = completion }
  func answer(_ value: Bool) { completion(value) }
}

@Test @MainActor func speechPermissionCanReturnOnBackgroundQueueWithoutActorViolation() async {
  let granted = await SpeechPermissionCallback.request { completion in
    let block = LegacyPermissionBlock(completion)
    DispatchQueue.global(qos: .default).async { block.answer(true) }
  }
  #expect(granted)
}

@Test @MainActor func speechPermissionDenialCrossesTheSameBackgroundBoundary() async {
  let granted = await SpeechPermissionCallback.request { completion in
    let block = LegacyPermissionBlock(completion)
    DispatchQueue.global(qos: .default).async { block.answer(false) }
  }
  #expect(!granted)
}
