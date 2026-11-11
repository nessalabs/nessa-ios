import NessaDesignSystem
import SwiftUI

/// One channel's chats, newest first, opened from the sidebar, with a composer that starts a
/// new chat in the channel: its agent works in the channel's folder, as on the desktop.
struct ChannelChatsView: View {
  @ObservedObject var store: MessagesViewModel
  let channel: NessaChannel
  @ObservedObject var dictation: DictationViewModel
  let onOpen: (String) -> Void
  /// A chat was made in this channel for the composer's message; the caller opens it and sends.
  let onStart: (_ conversationID: String, _ first: HomeFirstMessage) -> Void
  var body: some View {
    let chats = store.conversations(inChannel: channel.id)
    List {
      Group {
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
    .scrollDismissesKeyboard(.interactively)
    .messagesAmbientGround()
    .messagesBar(edge: .bottom) {
      NewChatComposer(store: store, dictation: dictation, channel: channel, onStart: onStart)
        .padding(.bottom, MessagesStyle.bottomInset)
    }
    .navigationTitle(channel.name)
  }
}
