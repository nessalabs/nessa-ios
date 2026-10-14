import NessaDesignSystem
import SwiftUI

struct NessaThreadView: View {
  @ObservedObject var store: MessagesViewModel
  let conversationID: String
  @StateObject private var dictation: DictationViewModel
  let autoFocusComposer: Bool
  init(
    store: MessagesViewModel, conversationID: String, dictation: DictationViewModel,
    autoFocusComposer: Bool = false
  ) {
    self.store = store
    self.conversationID = conversationID
    self.autoFocusComposer = autoFocusComposer
    _dictation = StateObject(wrappedValue: dictation)
  }
  @StateObject private var messageContext = MessageContextController()
  @State private var nearBottom = true
  @State private var bottomVisible = true
  @State private var position = ScrollPosition(edge: .bottom)
  @State private var scrollOffset: CGFloat = 0
  @StateObject private var composer = ComposerDraftViewModel()
  @State private var details = false
  @State private var hasLoadedHistory = false
  /// Until the reader scrolls away from the newest message, the thread stays pinned there
  /// as late layout (photos, the composer's height, streamed text) grows the content.
  @State private var readerScrolled = false
  /// Scrolls that settle before this were started by layout, not by the reader. A reference,
  /// so stamping it on every layout change doesn't re-render the thread.
  @State private var layoutClock = LayoutSettleClock()
  nonisolated private static func scrollRange(_ geometry: ScrollGeometry) -> CGFloat {
    geometry.contentSize.height + geometry.contentInsets.bottom - geometry.containerSize.height
  }
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private var current: NessaConversationView? {
    store.views[conversationID]
  }
  private var name: String { store.agentName(for: conversationID) }
  private var working: Bool { current?.messages.contains { $0.status == "running" } == true }
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
  private var replyBubbleCount: Int {
    (current?.messages ?? []).reduce(0) { $0 + $1.displayBubbles.count }
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
                  replyCount: replies.count(for: message.id), arrivesWithTurn: true,
                  onReply: { composer.reply = $0 }, onOpenThread: { composer.reply = $0 })
              }
              if turn.status == "running" {
                TypingIndicator()
                  .transition(MessagesStyle.bubbleInsertion(outgoing: false))
              }
              if let error = turn.error {
                Text(error).font(MessagesStyle.caption).foregroundStyle(MessagesStyle.danger)
              }
            }
            // A new turn arrives as the reader's own sent bubble, so the whole turn rises
            // out of the composer; replies inside it then grow in on their own.
            .transition(MessagesStyle.bubbleInsertion(outgoing: true))
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
            .onScrollVisibilityChange { visible in
              withAnimation(reduceMotion ? nil : NessaMotion.morph) { bottomVisible = visible }
            }
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
        .onScrollPhaseChange { _, phase, context in
          // Only the reader's own scrolls decide it: a drag releases the pin at once, and
          // any scroll that comes to rest (a drag, a status-bar tap, VoiceOver) settles it
          // by where it stopped. The system's own scroll after a layout change (the
          // keyboard rising) is not the reader's, so it re-pins instead of releasing.
          if phase == .interacting {
            readerScrolled = true
          } else if phase == .idle {
            let away =
              Self.scrollRange(context.geometry) - context.geometry.contentOffset.y
              > MessagesStyle.followDistance
            if Date() < layoutClock.settlesAt {
              if !readerScrolled && away && composer.reply == nil {
                position.scrollTo(edge: .bottom)
              }
            } else {
              readerScrolled = away
            }
          }
        }
        .onScrollGeometryChange(for: CGFloat.self, of: Self.scrollRange) { old, new in
          // Content or container grew under the reader: keep the newest message in place.
          // Shrinking never hides the newest message, so it needs nothing.
          guard new > old else { return }
          layoutClock.settlesAt = Date().addingTimeInterval(MessagesStyle.layoutSettleWindow)
          if !readerScrolled && composer.reply == nil { position.scrollTo(edge: .bottom) }
        }
        .onChange(of: current != nil, initial: true) { _, loaded in
          hasLoadedHistory = loaded
        }
        .onChange(of: current?.messages.last) { _, _ in
          followLatest(animated: animateMessages)
        }
        .messagesBar(edge: .bottom) {
          if composer.reply == nil {
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
                  .transition(
                    .scale(scale: MessagesStyle.swapScale, anchor: .trailing)
                      .combined(with: .opacity))
              }
              MessageComposer(
                draft: $composer.text, reply: $composer.reply, attachments: $composer.attachments,
                recipient: name,
                dictation: dictation,
                sending: store.sending, connected: store.connected,
                attachmentPolicy: store.attachmentPolicy,
                submissionAllowed: store.canSubmit(in: conversationID),
                submissionUnavailableReason: store.submissionUnavailableReason(in: conversationID),
                autoFocus: autoFocusComposer, working: working, onSend: send)
            }
          }
        }
    }
    .messagesAmbientGround()
    .messagesBar(edge: .top) {
      ThreadHeader(
        name: name, onBack: { dismiss() }, onDetails: { details = true }, working: working)
        .messagesHeaderBlur(scrollOffset: scrollOffset)
    }
    .environment(\.messageContext, messageContext)
    .blur(
      radius: composer.reply != nil
        ? MessagesStyle.replyBackgroundBlur
        : (messageContext.selection == nil ? 0 : MessagesStyle.contextBackgroundBlur)
    )
    .accessibilityHidden(messageContext.selection != nil || composer.reply != nil)
    .overlay {
      if composer.reply != nil {
        ReplyThreadView(
          replies: replies, conversationID: conversationID, agentName: name,
          store: store, selection: $composer.reply, draft: $composer.text,
          attachments: $composer.attachments,
          dictation: dictation,
          onDetails: { details = true }, onSend: send
        )
        .blur(radius: messageContext.selection == nil ? 0 : MessagesStyle.contextBackgroundBlur)
        .accessibilityHidden(messageContext.selection != nil)
        .transition(.opacity)
      }
    }
    .overlay { MessageContextOverlay(controller: messageContext).ignoresSafeArea() }
    .animation(
      reduceMotion ? nil : MessagesStyle.messageFollowAnimation, value: composer.reply != nil
    )
    .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.5), trigger: replyBubbleCount) {
      old, new in
      hasLoadedHistory && old > 0 && new > old
    }
    .nessaHideNavigationBar()
    .nessaNativeBackSwipe()
    .sheet(isPresented: $details) {
      AgentDetailsView(name: name, conversationID: conversationID, store: store)
    }
    .task(id: store.connectionRevision) { await store.watchConversation(conversationID) }
    .onChange(of: store.acknowledgedCommands) { _, ids in
      composer.accept(ids, scope: store.deliveryScopeRevision)
    }
    .onChange(of: store.pendingCommands) { _, commands in
      if store.connected && store.pendingLoadError == nil {
        composer.retainPending(Set(commands.map(\.requestID)))
      }
    }
  }

  private func send() {
    nearBottom = true
    let captured = composer.begin(scope: store.deliveryScopeRevision)
    Task {
      let accepted = await store.send(
        captured.text, attachments: captured.attachments,
        reply: captured.reply, to: conversationID, identity: captured.identity)
      if accepted {
        composer.accept([captured.identity.requestID], scope: store.deliveryScopeRevision)
      }
      composer.accept(store.acknowledgedCommands, scope: store.deliveryScopeRevision)
      let knownQueue = store.connected && store.pendingLoadError == nil
      let pending = store.pendingCommands.contains { $0.requestID == captured.identity.requestID }
      composer.finished(captured.identity.requestID, keepPending: !knownQueue || pending)
    }
  }

  private func followLatest(animated: Bool) {
    guard nearBottom, composer.reply == nil else { return }
    withAnimation(animated ? MessagesStyle.messageFollowAnimation : nil) {
      position.scrollTo(edge: .bottom)
    }
  }
}

/// When layout last moved the thread; read only when a scroll comes to rest.
private final class LayoutSettleClock {
  var settlesAt = Date.distantPast
}
