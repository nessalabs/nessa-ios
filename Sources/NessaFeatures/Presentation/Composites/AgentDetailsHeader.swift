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

/// The top of the details sheet: one quiet row with the agent's disc, its name, what it is
/// for, and the model it answers with. Sized like a list header, not a profile page.
struct AgentDetailsHero: View {
  let name: String
  let profile: AgentProfile?
  let working: Bool
  private var model: String? {
    guard let profile, let id = profile.defaultModel else { return nil }
    return profile.models.first { $0.id == id }?.displayName ?? id
  }
  var body: some View {
    HStack(alignment: .center, spacing: NessaSpacing.sm) {
      AgentAvatar(name: name, size: AgentDetailsStyle.heroAvatar, working: working)
      VStack(alignment: .leading, spacing: NessaSpacing.xxs) {
        Text(name).font(AgentDetailsStyle.title).lineLimit(1)
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
          }.padding(.top, NessaSpacing.xxs)
        }
      }
      Spacer(minLength: 0)
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
