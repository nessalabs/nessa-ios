import SwiftUI

/// The round mark beside a row in a multi-select list. Unselected it is a quiet grey ring;
/// selected it fills white with a dark tick and pops in on a small spring.
public struct NessaSelectionMark: View {
  private let selected: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  public init(selected: Bool) { self.selected = selected }
  public var body: some View {
    ZStack {
      Circle().strokeBorder(
        NessaColor.foreground.opacity(MessagesStyle.selectionRingOpacity),
        lineWidth: MessagesStyle.selectionRingWidth
      )
      .opacity(selected ? 0 : 1)
      Group {
        Circle().fill(NessaColor.foreground)
        Image(systemName: "checkmark").font(MessagesStyle.selectionTick)
          .foregroundStyle(NessaColor.background)
      }
      .scaleEffect(selected ? 1 : MessagesStyle.selectionPopScale)
      .opacity(selected ? 1 : 0)
    }
    .frame(width: MessagesStyle.selectionMark, height: MessagesStyle.selectionMark)
    .animation(reduceMotion ? nil : MessagesStyle.selectionPop, value: selected)
    // Only a mark being chosen ticks; clearing the whole selection at once stays silent.
    .sensoryFeedback(.selection, trigger: selected) { _, new in new }
    .accessibilityHidden(true)
  }
}
