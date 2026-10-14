import NessaDesignSystem
import SwiftUI

/// The agent's disc and name, in the sheet's header row beside the close button.
struct AgentDetailsIdentity: View {
  let name: String
  let working: Bool
  var body: some View {
    HStack(spacing: NessaSpacing.sm) {
      AgentAvatar(name: name, size: AgentDetailsStyle.heroAvatar, working: working)
      Text(name).font(AgentDetailsStyle.title).lineLimit(1).truncationMode(.tail)
    }.accessibilityElement(children: .combine)
  }
}

/// Under the header row: what the agent is for and the model it answers with.
struct AgentDetailsSummary: View {
  let profile: AgentProfile?
  let working: Bool
  private var model: String? {
    guard let profile, let id = profile.defaultModel else { return nil }
    return profile.models.first { $0.id == id }?.displayName ?? id
  }
  /// False when there is nothing to show, so the sheet leaves no empty gap for it.
  var hasContent: Bool {
    profile?.description?.isEmpty == false || working || model != nil
  }
  var body: some View {
    VStack(alignment: .leading, spacing: NessaSpacing.xs) {
      if let description = profile?.description, !description.isEmpty {
        Text(description).font(AgentDetailsStyle.subtitle)
          .foregroundStyle(MessagesStyle.secondary).lineLimit(2)
      }
      if working || model != nil {
        HStack(spacing: NessaSpacing.xs) {
          if working {
            NessaChip("Working", tint: MessagesStyle.foreground)
              .transition(.scale.combined(with: .opacity))
          }
          if let model { NessaChip(model, symbol: "cpu") }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
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
