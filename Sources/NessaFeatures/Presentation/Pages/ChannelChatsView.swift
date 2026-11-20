import NessaDesignSystem
import SwiftUI

/// One channel's chats, newest first, opened from the sidebar, with a composer that starts a
/// new chat in the channel: its agent works in the channel's folder, as on the desktop.
struct ChannelChatsView: View {
  @ObservedObject var store: MessagesViewModel
  let channel: NessaChannel
  @ObservedObject var dictation: DictationViewModel
  /// Hands back a first message whose chat couldn't be made.
  @ObservedObject var outgoing: OutgoingMessagesViewModel
  let onOpen: (String) -> Void
  /// Starts a chat in this channel with the composer's message; the caller opens it at once.
  let onStart: (HomeFirstMessage) -> Void
  @State private var draft = ""
  @State private var reply: MessageReply?
  @State private var attachments: [DraftAttachment] = []
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
        sending: store.busy, connected: store.connected,
        attachmentPolicy: store.attachmentPolicy,
        submissionAllowed: store.canCreateChat,
        placeholder: "Message \(channel.name)",
        endsEditingOnSend: true,
        onSend: start)
        .padding(.bottom, MessagesStyle.bottomInset)
    }
    .navigationTitle(channel.name)
    .onAppear(perform: takeReturned)
    .onChange(of: outgoing.returned.isEmpty) { _, _ in takeReturned() }
  }

  /// A message whose chat couldn't be made comes back here, unless something new is typed.
  private func takeReturned() {
    guard draft.isEmpty, attachments.isEmpty,
      let first = outgoing.takeReturned(channel: channel.isDefault ? nil : channel.channelId)
    else { return }
    draft = first.text
    attachments = first.attachments
  }

  /// The draft moves to the new chat, which opens at once and shows whether it got through.
  private func start() {
    let first = HomeFirstMessage(text: draft, attachments: attachments)
    draft = ""
    attachments = []
    onStart(first)
  }
}
