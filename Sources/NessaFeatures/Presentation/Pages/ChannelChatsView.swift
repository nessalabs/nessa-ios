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
  @State private var draft = ""
  @State private var reply: MessageReply?
  @State private var attachments: [DraftAttachment] = []
  @State private var starting = false
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
      MessageComposer(
        draft: $draft, reply: $reply, attachments: $attachments,
        recipient: channel.name, dictation: dictation,
        sending: starting || store.busy, connected: store.connected,
        attachmentPolicy: store.attachmentPolicy,
        submissionAllowed: store.canCreateChat && !starting,
        placeholder: "Message \(channel.name)",
        endsEditingOnSend: true,
        onSend: start)
        .padding(.bottom, MessagesStyle.bottomInset)
    }
    .navigationTitle(channel.name)
  }

  private func start() {
    let first = HomeFirstMessage(text: draft, attachments: attachments)
    starting = true
    Task {
      defer { starting = false }
      // The default channel is no stored channel: a chat made without one lands there.
      guard let id = await store.create(channel: channel.isDefault ? nil : channel.channelId)
      else { return }
      // The draft moves to the new chat, which sends it; a chat that could not be made keeps
      // it here.
      draft = ""
      attachments = []
      onStart(id, first)
    }
  }
}
