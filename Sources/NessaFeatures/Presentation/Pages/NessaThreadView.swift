import NessaDesignSystem
import SwiftUI

struct NessaThreadView: View {
  @ObservedObject var store: MessagesViewModel
  let conversationID: String
  @StateObject private var messageContext = MessageContextController()
  @State private var nearBottom = true
  @State private var scrollOffset: CGFloat = 0
  @State private var attachments: [DraftAttachment] = []
  @State private var draft = ""
  @State private var reply: MessageReply?
  @State private var details = false
  @Environment(\.dismiss) private var dismiss
  private var current: NessaConversationView? {
    store.views[conversationID]
  }
  private var name: String { store.agentName(for: conversationID) }
  var body: some View {
    ScrollViewReader { proxy in
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
              if let images = turn.attachments, !images.isEmpty {
                HStack {
                  Spacer(minLength: MessagesStyle.bubbleGutter)
                  PhotoAttachmentsGroup(
                    attachments: images,
                    reaction: store.reaction(message: turn.id + ":photos", in: conversationID),
                    onReact: { emoji in
                      store.react(emoji, message: turn.id + ":photos", in: conversationID)
                    },
                    onReply: {
                      reply = MessageReply(
                        id: turn.id + ":photos", author: "You", text: "\(images.count) photos")
                    }
                  ) { attachment in
                    await store.imageData(for: attachment)
                  }
                }
              }
              if !turn.userText.isEmpty {
                MessageBubble(
                  text: turn.userText, outgoing: true,
                  onReply: {
                    reply = MessageReply(id: turn.id + ":user", author: "You", text: turn.userText)
                  },
                  reaction: store.reaction(message: turn.id + ":user", in: conversationID)
                ) { emoji in
                  store.react(emoji, message: turn.id + ":user", in: conversationID)
                }
              }
              ForEach(turn.displayBubbles) { fragment in
                MessageBubble(
                  text: fragment.text, outgoing: false,
                  onReply: {
                    reply = MessageReply(
                      id: turn.id + ":" + fragment.id, author: name, text: fragment.text)
                  },
                  reaction: store.reaction(message: turn.id + ":" + fragment.id, in: conversationID)
                ) { emoji in
                  store.react(emoji, message: turn.id + ":" + fragment.id, in: conversationID)
                }
              }
              if turn.status == "running" {
                TypingIndicator()
              }
              if let error = turn.error {
                Text(error).font(MessagesStyle.caption).foregroundStyle(MessagesStyle.danger)
              }
            }
          }
          ForEach(current?.permissions ?? []) { permission in
            PermissionReview(permission: permission) { option in
              Task { await store.answer(permission, option: option, in: conversationID) }
            }
          }
          if let error = current?.interactionViewError {
            Text(error).font(MessagesStyle.caption).foregroundStyle(MessagesStyle.secondary)
          }
          Color.clear.frame(height: 1).id("bottom")
        }.padding(.horizontal, NessaSpacing.sm).padding(.top, NessaSpacing.sm).padding(
          .bottom, NessaSpacing.md)
      }.defaultScrollAnchor(.bottom, for: .initialOffset).messagesTrackScroll(offset: $scrollOffset)
        .messagesScrollEdges().scrollDismissesKeyboard(.interactively)
        .onScrollGeometryChange(for: Bool.self) { geometry in
          geometry.contentSize.height - geometry.contentOffset.y - geometry.containerSize.height
            < MessagesStyle.followDistance
        } action: { _, value in
          nearBottom = value
        }
        .onChange(of: current?.messages.count) { _, _ in
          if nearBottom { proxy.scrollTo("bottom", anchor: .bottom) }
        }
        .onChange(of: current?.messages.last?.parts.last?.text) { _, _ in
          if nearBottom { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }
    .background(MessagesStyle.background)
    .messagesBar(edge: .top) {
      ThreadHeader(name: name, onBack: { dismiss() }, onDetails: { details = true })
        .messagesHeaderBlur(scrollOffset: scrollOffset)
    }
    .messagesBar(edge: .bottom) {
      MessageComposer(
        draft: $draft, reply: $reply, attachments: $attachments, recipient: name,
        sending: store.sending,
        connected: store.connected, attachmentPolicy: store.attachmentPolicy
      ) {
        nearBottom = true
        let text = draft
        let selected = attachments
        let selectedReply = reply
        let message =
          selectedReply.map {
            "> " + String($0.text.prefix(500)).replacingOccurrences(of: "\n", with: "\n> ") + "\n\n"
              + text
          } ?? text
        Task {
          if await store.send(message, attachments: selected, to: conversationID) {
            if draft == text { draft = "" }
            if reply == selectedReply { reply = nil }
            attachments.removeAll { item in selected.contains { $0.id == item.id } }
          }
        }
      }
    }
    .environment(\.messageContext, messageContext)
    .blur(radius: messageContext.selection == nil ? 0 : MessagesStyle.contextBackgroundBlur)
    .accessibilityHidden(messageContext.selection != nil)
    .overlay { MessageContextOverlay(controller: messageContext).ignoresSafeArea() }
    .nessaHideNavigationBar()
    .nessaNativeBackSwipe()
    .sheet(isPresented: $details) {
      AgentDetailsView(name: name, conversationID: conversationID, store: store)
    }
    .task(id: conversationID) {
      while !Task.isCancelled && store.connected {
        await store.refresh(conversationID)
        do { try await Task.sleep(for: .seconds(2)) } catch { break }
      }
    }
  }
}
