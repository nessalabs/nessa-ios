import CoreGraphics
import Testing

@testable import NessaFeatures

/// Measured on an iPhone 17 Pro at the bottom of a thread with the keyboard down: a 1620 pt
/// list in a 642 pt container under a 144 pt header and over an 88 pt composer rests at 834.
@Test func bottomOffsetMatchesTheListAtRestAgainstTheComposer() {
  let bottom = ThreadScrollMetrics.bottomOffset(
    contentHeight: 1620, containerHeight: 642, topInset: 144)
  #expect(bottom == 834)
}
