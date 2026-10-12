import NessaDesignSystem
import SwiftUI

struct NessaThreadView: View {
  @ObservedObject var store: MessagesViewModel
  let conversationID: String
  @StateObject private var dictation: DictationViewModel
  init(store: MessagesViewModel, conversationID: String, dictation: DictationViewModel) {
    self.store = store
    self.conversationID = conversationID
    _dictation = StateObject(wrappedValue: dictation)
  }
  @StateObject private var messageContext = MessageContextController()
  @State private var nearBottom = true
  @State private var bottomVisible = true
  @State private var position = ScrollPosition(edge: .bottom)
  @State private var scrollOffset: CGFloat = 0
  @State private var attachments: [DraftAttachment] = []
  @State private var draft = ""
  @State private var reply: MessageReply?
  @State private var details = false
  @State private var hasLoadedHistory = false
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private var current: NessaConversationView? {
    store.views[conversationID]
  }
  private var name: String { store.agentName(for: conversationID) }
  // Content edits keep their identity, so streamed text doesn't replay the entrance.
  private var messageStructure: [String] {
    (current?.messages ?? []).flatMap { turn in
      var ids = [turn.id]
      if turn.attachments?.isEmpty == false { ids.append(turn.id + ":photos") }
      if !turn.userText.isEmpty { ids.append(turn.id + ":user") }
      ids += turn.displayBubbles.map { turn.id + ":" + $0.id }
      if turn.status == "running" { ids.append(turn.id + ":typing") }
      return ids
    }
  }
  var body: some View {
    let animateMessages = hasLoadedHistory && !reduceMotion
    let replies = store.replyProjection(in: conversationID)
    Group {
      ScrollView {
        LazyVStack(spacing: MessagesStyle.groupSpacing) {
          if current?.messages.isEmpty == true {
            Text("Message \(name) to get started.").font(MessagesStyle.caption).foregroundStyle(
              MessagesStyle.secondary)
          }
          if current?.truncated == true {
            Text("Showing recent messages").font(MessagesStyle.caption).foregroundStyle(
              MessagesStyle.secondary)
          }
          ForEach(current?.messages ?? []) { turn in
            VStack(spacing: MessagesStyle.bubbleSpacing) {
              ForEach(replies.messages(in: turn.id)) { message in
                ConversationMessageView(
                  message: message, conversationID: conversationID,
                  store: store, parent: replies.parent(of: message),
                  replyCount: replies.count(for: message.id),
                  onReply: { reply = $0 }, onOpenThread: { reply = $0 })
              }
              if turn.status == "running" {
                TypingIndicator()
                  .transition(MessagesStyle.bubbleInsertion(outgoing: false))
              }
              if let error = turn.error {
                Text(error).font(MessagesStyle.caption).foregroundStyle(MessagesStyle.danger)
              }
            }
            .transition(MessagesStyle.messageInsertion)
          }
          ForEach(current?.permissions ?? []) { permission in
            PermissionReview(permission: permission) { option in
              Task { await store.answer(permission, option: option, in: conversationID) }
            }.disabled(!store.connected)
          }
          if let error = current?.interactionViewError {
            Text(error).font(MessagesStyle.caption).foregroundStyle(MessagesStyle.secondary)
          }
          Color.clear.frame(height: 1).id("bottom")
            .onScrollVisibilityChange { bottomVisible = $0 }
        }
        .animation(
          animateMessages ? MessagesStyle.bubbleEntranceAnimation : nil,
          value: messageStructure
        )
        .padding(.horizontal, NessaSpacing.sm).padding(.top, NessaSpacing.sm).padding(
          .bottom, NessaSpacing.md)
      }.scrollPosition($position, anchor: .bottom)
        .defaultScrollAnchor(.bottom, for: .initialOffset).messagesTrackScroll(
          offset: $scrollOffset
        )
        .messagesScrollEdges().scrollDismissesKeyboard(.interactively)
        .onScrollGeometryChange(for: Bool.self) { geometry in
          geometry.contentSize.height - geometry.contentOffset.y - geometry.containerSize.height
            < MessagesStyle.followDistance
        } action: { _, value in
          nearBottom = value
        }
        .onChange(of: current != nil, initial: true) { _, loaded in
          hasLoadedHistory = loaded
        }
        .onChange(of: current?.messages.last) { _, _ in
          followLatest(animated: animateMessages)
        }
        .messagesBar(edge: .bottom) {
          if reply == nil {
            VStack(spacing: NessaSpacing.xs) {
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
                draft: $draft, reply: $reply, attachments: $attachments, recipient: name,
                dictation: dictation,
                sending: store.sending, connected: store.connected,
                attachmentPolicy: store.attachmentPolicy, onSend: send)
            }
          }
        }
    }
    .background(MessagesStyle.background)
    .messagesBar(edge: .top) {
      ThreadHeader(name: name, onBack: { dismiss() }, onDetails: { details = true })
        .messagesHeaderBlur(scrollOffset: scrollOffset)
    }
    .environment(\.messageContext, messageContext)
    .blur(
      radius: reply != nil
        ? MessagesStyle.replyBackgroundBlur
        : (messageContext.selection == nil ? 0 : MessagesStyle.contextBackgroundBlur)
    )
    .accessibilityHidden(messageContext.selection != nil || reply != nil)
    .overlay {
      if reply != nil {
        ReplyThreadView(
          replies: replies, conversationID: conversationID, agentName: name,
          store: store, selection: $reply, draft: $draft, attachments: $attachments,
          dictation: dictation,
          onDetails: { details = true }, onSend: send
        )
        .blur(radius: messageContext.selection == nil ? 0 : MessagesStyle.contextBackgroundBlur)
        .accessibilityHidden(messageContext.selection != nil)
        .transition(.opacity)
      }
    }
    .overlay { MessageContextOverlay(controller: messageContext).ignoresSafeArea() }
    .animation(reduceMotion ? nil : MessagesStyle.messageFollowAnimation, value: reply != nil)
    .nessaHideNavigationBar()
    .nessaNativeBackSwipe()
    .sheet(isPresented: $details) {
      AgentDetailsView(name: name, conversationID: conversationID, store: store)
    }
    .task(id: store.connectionRevision) { await store.watchConversation(conversationID) }
  }

  private func send() {
    nearBottom = true
    let text = draft
    let selected = attachments
    let selectedReply = reply
    Task {
      if await store.send(text, attachments: selected, reply: selectedReply, to: conversationID) {
        if draft == text { draft = "" }
        attachments.removeAll { item in selected.contains { $0.id == item.id } }
      }
    }
  }

  private func followLatest(animated: Bool) {
    guard nearBottom, reply == nil else { return }
    withAnimation(animated ? MessagesStyle.messageFollowAnimation : nil) {
      position.scrollTo(edge: .bottom)
    }
  }
}
