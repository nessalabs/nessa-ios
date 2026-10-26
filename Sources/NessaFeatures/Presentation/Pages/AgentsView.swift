import NessaDesignSystem
import SwiftUI

/// Every agent at a glance, as the desktop's Agents overview shows them: what needs the
/// person first, then what is working, what finished, and the rest. A chip narrows the list
/// to one group; every chat in one list is a tap away at the top.
struct AgentsView: View {
  @ObservedObject var store: MessagesViewModel
  let onOpen: (String) -> Void
  /// Every chat in one list, with search, selecting and archiving: the inbox.
  let onAllChats: () -> Void
  @State private var shown: AgentsGroup?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let glance = store.agentsGlance
    // A chosen group that has emptied (its last review answered) shows everything again,
    // rather than an empty screen with no chip chosen.
    let showing = shown.flatMap { glance.count($0) > 0 ? $0 : nil }
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        chips(glance, showing: showing)
        ForEach(AgentsGroup.allCases, id: \.self) { group in
          let ids = glance.ids(group)
          if !ids.isEmpty && (showing == nil || showing == group) {
            Text(group.title).font(MessagesStyle.sidebarSection)
              .foregroundStyle(MessagesStyle.secondary)
              .padding(.horizontal, MessagesStyle.horizontal)
              .padding(.top, MessagesStyle.agentsSectionGap).padding(.bottom, NessaSpacing.xs)
              .accessibilityAddTraits(.isHeader)
            ForEach(ids, id: \.self) { id in
              if group == .needsYou, let permission = store.views[id]?.permissions.first {
                approval(id, permission: permission)
              } else {
                row(id, group: group)
              }
            }
          }
        }
      }
      .padding(.bottom, NessaSpacing.xl)
    }
    .messagesScrollEdges()
    .messagesAmbientGround()
    // The title sits in the bar beside the back button, not as a large title under it, so
    // the list starts higher.
    .navigationTitle("Agents")
    .nessaInlineNavigationTitle()
    .toolbar {
      AgentsTitle()
      ToolbarItem(placement: .primaryAction) {
        Button(action: onAllChats) { NessaIcon(.chats) }
          .accessibilityLabel("All chats")
      }
    }
  }

  private func approval(_ id: String, permission: NessaPermission) -> some View {
    let channel = store.conversations.first { $0.id == id }?.channelId
    let channelName = store.channels.first { $0.id == channel && !$0.isDefault }?.name
    return PermissionCard(
      permission: permission,
      source: .init(chatName: store.chatName(id), channelName: channelName, onOpen: { onOpen(id) })
    ) { option in Task { await store.answer(permission, option: option, in: id) } }
    .padding(.horizontal, MessagesStyle.agentsCardGutter)
  }

  private func chips(_ glance: AgentsGlance, showing: AgentsGroup?) -> some View {
    ScrollView(.horizontal) {
      HStack(spacing: NessaSpacing.xs) {
        chip("All", selected: showing == nil) { shown = nil }
        ForEach(AgentsGroup.allCases, id: \.self) { group in
          let count = glance.count(group)
          if count > 0 {
            chip("\(group.title) \(count)", selected: showing == group) {
              shown = showing == group ? nil : group
            }
          }
        }
      }
      .padding(.horizontal, MessagesStyle.horizontal)
    }
    .scrollIndicators(.hidden)
    .padding(.top, NessaSpacing.sm)
  }

  private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
    Button {
      withAnimation(reduceMotion ? nil : NessaMotion.standard()) { action() }
    } label: {
      Text(title).font(MessagesStyle.preview.weight(selected ? .semibold : .regular))
        .padding(.horizontal, MessagesStyle.chipInset)
        .frame(height: MessagesStyle.chipHeight)
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
      HStack(spacing: MessagesStyle.agentsRowGap) {
        NessaIcon(.chats, size: MessagesStyle.rowIcon)
          .foregroundStyle(group == .earlier ? MessagesStyle.secondary : MessagesStyle.foreground)
        VStack(alignment: .leading, spacing: MessagesStyle.rowLineGap) {
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
      .padding(.vertical, MessagesStyle.agentsRowInset)
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

/// "Agents" in the bar's leading corner, beside the back button, bold and bare: on iOS 26 a
/// bar item gets a glass capsule of its own, which a title should not wear. It takes the
/// principal place's job, so that place holds nothing.
private struct AgentsTitle: ToolbarContent {
  var body: some ToolbarContent {
    #if os(iOS)
      if #available(iOS 26.0, *) {
        ToolbarItem(placement: .topBarLeading) { title }.sharedBackgroundVisibility(.hidden)
      } else {
        ToolbarItem(placement: .topBarLeading) { title }
      }
      ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) }
    #else
      ToolbarItem(placement: .navigation) { title }
    #endif
  }
  private var title: some View {
    // At its own width: a bar item is otherwise measured narrow and the title cut to "A…".
    Text("Agents").font(MessagesStyle.barTitle).fixedSize().accessibilityAddTraits(.isHeader)
  }
}
