import NessaDesignSystem
import SwiftUI

struct PinnedChatsGrid: View {
  @ObservedObject var store: MessagesViewModel
  let onOpen: (String) -> Void
  let onOpenComposer: (String) -> Void
  let onDelete: (String) -> Void
  var enabled = true
  var body: some View {
    LazyVGrid(
      columns: Array(repeating: GridItem(.flexible(), spacing: MessagesStyle.pinGap), count: 3),
      spacing: MessagesStyle.pinRowGap
    ) {
      ForEach(store.pinnedChats.filter { !store.isDeleting($0) }, id: \.self) { agent in
        Button {
          onOpen(agent)
        } label: {
          VStack(spacing: NessaSpacing.xs) {
            AgentAvatar(name: store.agentName(for: agent), size: MessagesStyle.pinnedAvatar)
              .overlay(alignment: .bottomTrailing) {
                if store.unreadChats.contains(agent) {
                  Image(systemName: "circle.fill").font(MessagesStyle.smallIcon).foregroundStyle(
                    MessagesStyle.outgoing)
                } else if store.mutedChats.contains(agent) {
                  Image(systemName: "bell.slash.fill").font(MessagesStyle.smallIcon)
                    .foregroundStyle(MessagesStyle.secondary)
                }
              }
            Text(store.chatName(agent)).font(MessagesStyle.pinLabel)
              .foregroundStyle(MessagesStyle.secondary).lineLimit(1)
          }.frame(maxWidth: .infinity)
        }.buttonStyle(.plain).disabled(!enabled)
          .accessibilityLabel("Open pinned chat \(store.chatName(agent))")
          .chatContextMenu(
            store: store, identifier: agent, enabled: enabled,
            onTap: { onOpen(agent) }, onCommit: onOpenComposer, onDelete: onDelete)
      }
    }.padding(.top, NessaSpacing.sm).padding(.bottom, NessaSpacing.xxs)
  }
}
