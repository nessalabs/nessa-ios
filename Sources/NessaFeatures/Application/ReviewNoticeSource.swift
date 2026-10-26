/// A connection that announces the reviews waiting on the person.
public protocol ReviewNoticeSource: Sendable {
  /// The latest announcement at once, if there is one, then each new one, until the
  /// connection ends.
  func waitingReviews() async -> AsyncStream<WaitingReviews>
}
