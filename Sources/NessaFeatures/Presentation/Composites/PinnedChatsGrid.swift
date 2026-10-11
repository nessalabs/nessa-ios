import NessaDesignSystem
import SwiftUI

struct PinnedChatsGrid: View {
  @ObservedObject var store: MessagesViewModel
  let onOpen: (String) -> Void
  @State private var deletingAgent: String?
  var body: some View {
    LazyVGrid(
      columns: Array(repeating: GridItem(.flexible(), spacing: MessagesStyle.pinGap), count: 3),
      spacing: MessagesStyle.pinRowGap
    ) {
      ForEach(store.pinnedChats, id: \.self) { agent in
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
        }.buttonStyle(.plain)
          .accessibilityLabel("Open pinned chat \(store.chatName(agent))")
          .contextMenu {
            Button("Unpin", systemImage: "pin.slash") { store.togglePin(agent) }
            Button("Mark as Unread", systemImage: "bubble") { store.markUnread(agent) }
            Button(
              store.mutedChats.contains(agent) ? "Show Alerts" : "Hide Alerts",
              systemImage: store.mutedChats.contains(agent) ? "bell" : "bell.slash"
            ) { store.toggleAlerts(agent) }
            Button("Delete", systemImage: "trash", role: .destructive) { deletingAgent = agent }
              .disabled(!store.hasConversation(agent) || !store.connected)
          } preview: {
            ChatConversationPreview(store: store, agent: agent)
          }
      }
    }.padding(.top, NessaSpacing.sm).padding(.bottom, NessaSpacing.xxs)
      .confirmationDialog(
        "Delete this conversation permanently?",
        isPresented: Binding(
          get: { deletingAgent != nil }, set: { if !$0 { deletingAgent = nil } }),
        titleVisibility: .visible
      ) {
        if let agent = deletingAgent {
          Button("Delete conversation", role: .destructive) {
            Task { await store.deleteConversation(for: agent) }
          }
        }
        Button("Cancel", role: .cancel) { deletingAgent = nil }
      } message: {
        Text(
          "This removes the conversation and its history from Nessa. The agent remains available.")
      }
  }
}
