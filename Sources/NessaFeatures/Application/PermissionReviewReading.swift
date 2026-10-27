/// A connection that reads what one waiting review asks. A view lists each review by its
/// key alone; its title, the exact tool input and the choices an answer may name are read
/// here, from the review's live owner.
public protocol PermissionReviewReading: Sendable {
  /// The review `review` waiting in `conversationID`. Throws once it no longer waits.
  func permissionReview(_ review: String, conversationID: String) async throws -> NessaPermission
}
