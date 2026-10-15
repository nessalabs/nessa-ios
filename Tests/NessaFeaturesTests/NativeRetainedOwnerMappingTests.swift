import Testing

@testable import NessaFeatures

@Test func currentNativeOwnerCapturesPreserveRecoveryAndIndependentFailures() async throws {
  try await Task.detached { try verifyCurrentOwnerCaptures() }.value
}
