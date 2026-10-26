import NessaDesignSystem
import SwiftUI

/// The chats archived from Agents, newest first, opened from Settings. A swipe brings one
/// back; the gateway decides which chats are archived, so the list is read each time it opens.
struct ArchivedChatsView: View {
  @ObservedObject var store: MessagesViewModel
  let onOpen: (String) -> Void
  var body: some View {
    List {
      Group {
        if store.archivedConversations.isEmpty {
          Text("No archived chats.").font(MessagesStyle.body)
            .foregroundStyle(MessagesStyle.secondary).padding(.vertical, NessaSpacing.xl)
        }
        ForEach(store.archivedConversations) { conversation in
          Button { onOpen(conversation.id) } label: {
            ConversationRow(
              conversation: conversation, agentName: store.agentName(for: conversation.id)
            )
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button("Unarchive", systemImage: "tray.and.arrow.up") {
              Task { await store.setArchived(false, conversationID: conversation.id) }
            }
            .tint(MessagesStyle.archiveAction)
            .disabled(!store.connected)
          }
        }
      }
      .listRowInsets(
        EdgeInsets(
          top: 0, leading: MessagesStyle.horizontal, bottom: 0, trailing: MessagesStyle.horizontal)
      )
      .listRowSeparator(.hidden).listRowBackground(Color.clear)
    }
    .listStyle(.plain).scrollContentBackground(.hidden)
    .environment(\.defaultMinListRowHeight, 0)
    .task(id: store.connected) { await store.loadArchived() }
    .refreshable { await store.loadArchived() }
    .messagesScrollEdges()
    .messagesAmbientGround()
    .navigationTitle("Archived")
    .nessaInlineNavigationTitle()
    .toolbar { BarTitle("Archived") }
  }
}
