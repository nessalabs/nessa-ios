import NessaDesignSystem
import SwiftUI

/// One channel's chats, newest first, opened from the sidebar.
struct ChannelChatsView: View {
  @ObservedObject var store: MessagesViewModel
  let channel: NessaChannel
  let onOpen: (String) -> Void
  var body: some View {
    let chats = store.conversations(inChannel: channel.id)
    List {
      Group {
        Text(channel.folder).font(NessaType.mono).foregroundStyle(MessagesStyle.secondary)
          .lineLimit(1).truncationMode(.head)
        if chats.isEmpty {
          Text("No chats in this channel yet.").font(MessagesStyle.body)
            .foregroundStyle(MessagesStyle.secondary).padding(.vertical, NessaSpacing.xl)
        }
        ForEach(chats) { conversation in
          Button { onOpen(conversation.id) } label: {
            ConversationRow(
              conversation: conversation, agentName: store.agentName(for: conversation.id)
            )
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
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
    .messagesAmbientGround()
    .navigationTitle(channel.name)
  }
}
