import NessaDesignSystem
import SwiftUI

struct ReplyThreadView: View {
  let replies: ConversationReplies
  let conversationID: String
  let agentName: String
  @ObservedObject var store: MessagesViewModel
  @Binding var selection: MessageReply?
  @Binding var draft: String
  @Binding var attachments: [DraftAttachment]
  @ObservedObject var dictation: DictationViewModel
  let onSend: () -> Void
  @State private var nearBottom = true
  @State private var bottomVisible = true
  @State private var position = ScrollPosition(edge: .bottom)
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private var root: ConversationMessage? { selection.flatMap { replies.root(for: $0.id) } }
  private var thread: [ConversationMessage] { root.map { replies.replies(to: $0.id) } ?? [] }

  var body: some View {
    let turnIDs = Set(thread.map(\.turnID) + [root?.turnID].compactMap { $0 })
    Group {
      ScrollView {
        LazyVStack(spacing: MessagesStyle.groupSpacing) {
          if let root {
            message(root)
          } else if let selection {
            MessageBubble(text: selection.text, outgoing: selection.author == "You")
          }
          ForEach(thread) { message($0) }
          if let lastTurn = thread.last?.turnID,
            store.views[conversationID]?.messages.first(where: { $0.id == lastTurn })?.status
              == "running"
          {
            TypingIndicator().transition(MessagesStyle.typingTransition)
          }
          ForEach(store.views[conversationID]?.messages.filter { turnIDs.contains($0.id) } ?? []) {
            turn in
            if let error = turn.error {
              Text(error).font(MessagesStyle.caption).foregroundStyle(MessagesStyle.danger)
            }
          }
          ForEach(
            store.views[conversationID]?.permissions.filter { turnIDs.contains($0.executionId) }
              ?? []
          ) { permission in
            PermissionReview(permission: permission) { option in
              Task { await store.answer(permission, option: option, in: conversationID) }
            }
          }
          Color.clear.frame(height: 1).id("reply-bottom")
            .onScrollVisibilityChange { bottomVisible = $0 }
        }.padding(NessaSpacing.sm)
          .animation(
            reduceMotion ? nil : MessagesStyle.bubbleEntranceAnimation,
            value: thread.map(\.id))
      }
      .scrollPosition($position, anchor: .bottom)
      .defaultScrollAnchor(.bottom, for: .initialOffset)
      .defaultScrollAnchor(.bottom, for: .alignment)
      .scrollDismissesKeyboard(.interactively)
      .onScrollGeometryChange(for: Bool.self) { geometry in
        geometry.contentSize.height - geometry.contentOffset.y - geometry.containerSize.height
          < MessagesStyle.followDistance
      } action: { _, value in
        nearBottom = value
      }
      .onChange(of: thread) { _, _ in
        guard nearBottom else { return }
        withAnimation(reduceMotion ? nil : MessagesStyle.messageFollowAnimation) {
          position.scrollTo(edge: .bottom)
        }
      }
      .messagesBar(edge: .bottom) {
        VStack(spacing: NessaSpacing.xs) {
          if store.pendingLoadError != nil { PendingDeliveryUnavailable(store: store) }
          ForEach(store.pendingSubmissions(in: conversationID), id: \.requestID) { command in
            PendingCommandActions(command: command, store: store)
          }
          if !bottomVisible {
            HStack {
              Spacer()
              MessagesJumpToLatest {
                withAnimation(reduceMotion ? nil : MessagesStyle.jumpToLatestAnimation) {
                  position.scrollTo(edge: .bottom)
                }
              }
            }.padding(.horizontal, MessagesStyle.horizontal)
              .transition(.opacity)
          }
          MessageComposer(
            draft: $draft, reply: $selection, attachments: $attachments,
            recipient: agentName, dictation: dictation, sending: store.sending,
            connected: store.connected,
            attachmentPolicy: store.attachmentPolicy,
            submissionAllowed: store.canSubmit(in: conversationID),
            submissionUnavailableReason: store.submissionUnavailableReason(in: conversationID),
            placeholder: "Reply", autoFocus: true,
            onSend: {
              nearBottom = true
              onSend()
            })
        }
      }
    }
    .background(MessagesStyle.background.opacity(MessagesStyle.replyPreviewOpacity))
  }

  private func message(_ message: ConversationMessage) -> some View {
    ConversationMessageView(
      message: message, conversationID: conversationID, store: store,
      onReply: { selection = $0 }, onOpenThread: { selection = $0 })
  }
}
