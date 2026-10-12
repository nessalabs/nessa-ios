import NessaDesignSystem
import SwiftUI

struct ConversationMessageView: View {
  let message: ConversationMessage
  let conversationID: String
  @ObservedObject var store: MessagesViewModel
  var parent: ConversationMessage? = nil
  var replyCount = 0
  let onReply: (MessageReply) -> Void
  let onOpenThread: (MessageReply) -> Void

  var body: some View {
    VStack(alignment: message.outgoing ? .trailing : .leading, spacing: NessaSpacing.xs) {
      if message.outgoing, let parent {
        ReplyQuotePreview(message: parent) { onOpenThread(parent.reply) }
      }
      content
      if replyCount > 0 {
        Button(replyCount == 1 ? "1 Reply" : "\(replyCount) Replies") {
          onOpenThread(message.reply)
        }.font(MessagesStyle.caption).tint(MessagesStyle.tapbackBackground)
          .padding(.horizontal, MessagesStyle.bubbleInset)
          .frame(maxWidth: .infinity, alignment: message.outgoing ? .trailing : .leading)
      }
    }
    .transition(MessagesStyle.bubbleInsertion(outgoing: message.outgoing))
  }

  @ViewBuilder private var content: some View {
    let reaction = store.reaction(message: message.id, in: conversationID)
    switch message.content {
    case .text(let text):
      MessageBubble(
        text: text, outgoing: message.outgoing,
        onReply: { onReply(message.reply) }, reaction: reaction
      ) { emoji in
        store.react(emoji, message: message.id, in: conversationID)
      }
    case .photos(let images):
      HStack {
        Spacer(minLength: MessagesStyle.bubbleGutter)
        PhotoAttachmentsGroup(
          attachments: images, reaction: reaction,
          onReact: { store.react($0, message: message.id, in: conversationID) },
          onReply: { onReply(message.reply) }
        ) { await store.imageData(for: $0) }
      }
    case .file(let file):
      HStack {
        Spacer(minLength: MessagesStyle.bubbleGutter)
        fileContent(file)
          .messageReaction(
            reaction: reaction, outgoing: message.outgoing,
            onReact: { store.react($0, message: message.id, in: conversationID) },
            onReply: { onReply(message.reply) }, preview: AnyView(fileContent(file)))
      }
    }
  }

  private func fileContent(_ file: NessaFileAttachment) -> some View {
    Label(file.name, systemImage: "doc").font(MessagesStyle.body)
      .padding(MessagesStyle.bubbleInset)
      .background(
        MessagesStyle.control,
        in: RoundedRectangle(cornerRadius: MessagesStyle.replyPreviewRadius))
  }
}

private struct ReplyQuotePreview: View {
  let message: ConversationMessage
  let onOpen: () -> Void
  var body: some View {
    Button(action: onOpen) {
      VStack(alignment: message.outgoing ? .trailing : .leading, spacing: NessaSpacing.xs) {
        HStack {
          if message.outgoing { Spacer(minLength: MessagesStyle.bubbleGutter) }
          VStack(alignment: .leading, spacing: NessaSpacing.xxs) {
            Text(message.author).font(MessagesStyle.caption)
            Text(message.summary).font(MessagesStyle.preview).lineLimit(2)
          }.padding(MessagesStyle.bubbleInset)
            .foregroundStyle(MessagesStyle.secondary)
            .background(
              (message.outgoing ? MessagesStyle.outgoing : MessagesStyle.incoming)
                .opacity(MessagesStyle.replyPreviewOpacity),
              in: RoundedRectangle(cornerRadius: MessagesStyle.replyPreviewRadius))
          if !message.outgoing { Spacer(minLength: MessagesStyle.bubbleGutter) }
        }
        ReplyConnector(outgoing: message.outgoing).padding(.horizontal, MessagesStyle.bubbleInset)
      }
    }.buttonStyle(.plain).accessibilityLabel("Reply to \(message.author): \(message.summary)")
  }
}
