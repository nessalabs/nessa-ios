import NessaDesignSystem
import SwiftUI

struct AgentDetailsIdentity: View {
  let name: String
  let compact: Bool
  var body: some View {
    HStack(spacing: NessaSpacing.sm) {
      AgentAvatar(
        name: name,
        size: compact ? AgentDetailsStyle.compactAvatar : AgentDetailsStyle.avatar)
      Text(name).font(compact ? MessagesStyle.title : AgentDetailsStyle.title)
        .lineLimit(1).truncationMode(.tail)
    }.accessibilityElement(children: .combine)
  }
}

struct AgentDetailsTabs: View {
  @Binding var selection: AgentDetailsTab
  var body: some View {
    MessagesSegmentedControl(
      labels: AgentDetailsTab.allCases.map(\.rawValue),
      selectedIndex: Binding(
        get: { AgentDetailsTab.allCases.firstIndex(of: selection) ?? 0 },
        set: { index in
          guard AgentDetailsTab.allCases.indices.contains(index) else { return }
          selection = AgentDetailsTab.allCases[index]
        }
      ),
      accessibilityLabel: "Agent details"
    )
  }
}
