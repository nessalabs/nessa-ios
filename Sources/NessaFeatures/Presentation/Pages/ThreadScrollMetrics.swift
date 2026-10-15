import CoreGraphics

/// Where the thread's list sits relative to its newest message.
enum ThreadScrollMetrics {
  /// The content offset at which the newest message rests just above the composer.
  ///
  /// The container is the visible height between the header and the composer, the insets
  /// already taken out, while the offset is measured from the top of the inset area: it is
  /// minus the top inset when the list is at its top. So the bottom is the content height less
  /// the container and the top inset; the bottom inset does not enter it.
  static func bottomOffset(contentHeight: CGFloat, containerHeight: CGFloat, topInset: CGFloat)
    -> CGFloat
  {
    contentHeight - containerHeight - topInset
  }
}
