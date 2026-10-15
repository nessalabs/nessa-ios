import SwiftUI

extension View {
  /// Shrinks the view's height to nothing (and back) on whatever animation the change runs
  /// in, top edge fixed, fading as it goes. A list row that collapses before it is removed
  /// leaves no gap for the rows below to slide through, so their text never passes over its
  /// fading text. Clip or mask after it, so the content stops at the shrinking edge.
  public func nessaCollapsed(_ collapsed: Bool) -> some View {
    NessaCollapseLayout(fraction: collapsed ? 0 : 1) { self }
      .opacity(collapsed ? 0 : 1)
  }
}

/// Reports a share of its content's height, so the height animates frame by frame.
private struct NessaCollapseLayout: Layout {
  var fraction: CGFloat
  var animatableData: CGFloat {
    get { fraction }
    set { fraction = newValue }
  }
  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let size = subviews.first?.sizeThatFits(proposal) ?? .zero
    return CGSize(width: size.width, height: size.height * max(fraction, 0))
  }
  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
  ) {
    subviews.first?.place(
      at: bounds.origin, anchor: .topLeading,
      proposal: ProposedViewSize(width: bounds.width, height: nil))
  }
}
