import NessaDesignSystem
import SwiftUI

/// The agent's face and name in one line, for the collapsed header.
struct AgentDetailsIdentity: View {
  let name: String
  var body: some View {
    HStack(spacing: NessaSpacing.xs) {
      AgentAvatar(name: name, size: AgentDetailsStyle.compactAvatar)
      Text(name).font(MessagesStyle.title).lineLimit(1).truncationMode(.tail)
    }.accessibilityElement(children: .combine)
  }
}

/// The top of the details sheet: the agent's disc glowing in the brand wash, its name,
/// what it is for, and the model it answers with.
struct AgentDetailsHero: View {
  let name: String
  let profile: AgentProfile?
  let working: Bool
  private var model: String? {
    guard let profile, let id = profile.defaultModel else { return nil }
    return profile.models.first { $0.id == id }?.displayName ?? id
  }
  var body: some View {
    VStack(spacing: NessaSpacing.sm) {
      ZStack {
        NessaWash(feathered: true)
          .frame(width: AgentDetailsStyle.heroWash, height: AgentDetailsStyle.heroWash)
        AgentAvatar(name: name, size: AgentDetailsStyle.heroAvatar, working: working)
      }
      .frame(height: AgentDetailsStyle.heroHeight)
      Text(name).font(AgentDetailsStyle.title).lineLimit(2).multilineTextAlignment(.center)
      if let description = profile?.description, !description.isEmpty {
        Text(description).font(AgentDetailsStyle.subtitle)
          .foregroundStyle(MessagesStyle.secondary).multilineTextAlignment(.center)
          .lineLimit(3)
      }
      HStack(spacing: NessaSpacing.xs) {
        if working {
          NessaChip("Working", symbol: "sparkles", tint: NessaColor.thinkingCurrent)
            .transition(.scale.combined(with: .opacity))
        }
        if let model { NessaChip(model, symbol: "cpu") }
      }
    }
    .frame(maxWidth: .infinity)
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
