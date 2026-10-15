import SwiftUI

/// Nessa's segmented selection: a quiet track with a lit pill that springs to the choice.
/// Assistive technologies see it as a standard segmented picker.
public struct MessagesSegmentedControl: View {
  public let labels: [String]
  public let accessibilityLabel: String
  @Binding public var selectedIndex: Int
  @Namespace private var pill
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  public init(
    labels: [String], selectedIndex: Binding<Int>, accessibilityLabel: String = "Selection"
  ) {
    self.labels = labels
    self.accessibilityLabel = accessibilityLabel
    self._selectedIndex = selectedIndex
  }
  public var body: some View {
    HStack(spacing: 0) {
      ForEach(labels.indices, id: \.self) { index in
        let selected = index == selectedIndex
        Button {
          withAnimation(reduceMotion ? nil : NessaMotion.morph) { selectedIndex = index }
        } label: {
          Text(labels[index]).font(AgentDetailsStyle.tabLabel)
            .foregroundStyle(selected ? NessaColor.foreground : NessaColor.mutedForeground)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
              if selected {
                Capsule().fill(NessaColor.muted)
                  .overlay(Capsule().strokeBorder(NessaColor.hairline, lineWidth: 0.5))
                  .matchedGeometryEffect(id: "pill", in: pill)
              }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(NessaPressStyle(scale: 0.97))
      }
    }
    .padding(AgentDetailsStyle.tabInset)
    .frame(height: AgentDetailsStyle.tabHeight)
    .background(NessaColor.card, in: Capsule())
    .overlay(Capsule().strokeBorder(NessaColor.hairline, lineWidth: 0.5))
    .sensoryFeedback(.selection, trigger: selectedIndex)
    .accessibilityRepresentation {
      Picker(accessibilityLabel, selection: $selectedIndex) {
        ForEach(labels.indices, id: \.self) { index in Text(labels[index]).tag(index) }
      }.pickerStyle(.segmented)
    }
  }
}
