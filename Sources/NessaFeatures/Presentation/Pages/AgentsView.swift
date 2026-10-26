import NessaDesignSystem
import SwiftUI

/// Every agent at a glance, as the desktop's Agents overview shows them: what needs the
/// person first, then what is working, what finished, and the rest. A chip narrows the list
/// to one group.
struct AgentsView: View {
  @ObservedObject var store: MessagesViewModel
  let onOpen: (String) -> Void
  @State private var shown: AgentsGroup?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let glance = store.agentsGlance
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        Text(glance.summary).font(MessagesStyle.greetingDetail)
          .foregroundStyle(MessagesStyle.secondary)
          .padding(.horizontal, MessagesStyle.horizontal)
        chips(glance)
        ForEach(AgentsGroup.allCases, id: \.self) { group in
          let ids = glance.ids(group)
          if !ids.isEmpty && (shown == nil || shown == group) {
            Text(group.title).font(MessagesStyle.sidebarSection)
              .foregroundStyle(MessagesStyle.secondary)
              .padding(.horizontal, MessagesStyle.horizontal)
              .padding(.top, NessaSpacing.lg).padding(.bottom, NessaSpacing.xxs)
              .accessibilityAddTraits(.isHeader)
            ForEach(ids, id: \.self) { row($0, group: group) }
          }
        }
      }
      .padding(.bottom, NessaSpacing.xl)
    }
    .messagesScrollEdges()
    .messagesAmbientGround()
    .navigationTitle("Agents")
  }

  private func chips(_ glance: AgentsGlance) -> some View {
    ScrollView(.horizontal) {
      HStack(spacing: NessaSpacing.xs) {
        chip("All", selected: shown == nil) { shown = nil }
        ForEach(AgentsGroup.allCases, id: \.self) { group in
          let count = glance.count(group)
          if count > 0 {
            chip("\(group.title) \(count)", selected: shown == group) {
              shown = shown == group ? nil : group
            }
          }
        }
      }
      .padding(.horizontal, MessagesStyle.horizontal)
    }
    .scrollIndicators(.hidden)
    .padding(.top, NessaSpacing.md)
  }

  private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
    Button {
      withAnimation(reduceMotion ? nil : NessaMotion.standard()) { action() }
    } label: {
      Text(title).font(MessagesStyle.preview.weight(selected ? .semibold : .regular))
        .padding(.horizontal, NessaSpacing.sm)
        .frame(height: AgentsStyle.chipHeight)
        .foregroundStyle(selected ? MessagesStyle.background : MessagesStyle.foreground)
        .background(
          selected ? AnyShapeStyle(MessagesStyle.foreground) : AnyShapeStyle(NessaColor.card),
          in: Capsule())
        .overlay(Capsule().stroke(NessaColor.hairline, lineWidth: selected ? 0 : 1))
    }
    .buttonStyle(.nessaPress)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private func row(_ id: String, group: AgentsGroup) -> some View {
    let conversation = store.conversations.first { $0.id == id }
    return Button { onOpen(id) } label: {
      HStack(spacing: NessaSpacing.sm) {
        NessaIcon(.chats, size: MessagesStyle.sidebarIcon - 2)
          .foregroundStyle(group == .earlier ? MessagesStyle.secondary : MessagesStyle.foreground)
        VStack(alignment: .leading, spacing: 2) {
          Text(store.chatName(id)).font(MessagesStyle.sidebarRow)
            .fontWeight(group == .finished ? .semibold : .regular)
            .lineLimit(1)
          Text(detail(conversation, group: group)).font(MessagesStyle.preview)
            .foregroundStyle(MessagesStyle.secondary).lineLimit(1)
            .nessaShimmer(active: group == .working)
        }
        Spacer(minLength: 0)
        if group == .needsYou || group == .working {
          Circle().fill(NessaColor.accent)
            .frame(width: MessagesStyle.statusDot, height: MessagesStyle.statusDot)
        }
      }
      .foregroundStyle(MessagesStyle.foreground)
      .padding(.horizontal, MessagesStyle.horizontal)
      .padding(.vertical, NessaSpacing.sm)
      .contentShape(Rectangle())
    }
    .buttonStyle(.nessaPress)
    .accessibilityLabel("\(store.chatName(id)), \(group.title)")
  }

  private func detail(_ conversation: NessaConversation?, group: AgentsGroup) -> String {
    switch group {
    case .needsYou: return "Waiting for your answer"
    case .working: return "\(store.agentName(for: conversation?.id ?? "")) is working…"
    case .finished, .earlier: return conversation?.preview ?? "New conversation"
    }
  }
}

private enum AgentsStyle {
  static let chipHeight: CGFloat = 32
}
