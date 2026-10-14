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
  @State private var position = ScrollPosition(edge: .bottom)
  @State private var scrollOffset: CGFloat = 0
  @StateObject private var composer = ComposerDraftViewModel()
  @State private var details = false
  @State private var hasLoadedHistory = false
  /// Until the reader scrolls away from the newest message, the thread stays pinned there
  /// as late layout (photos, the composer's height, streamed text) grows the content.
  @State private var readerScrolled = false
  /// Whether the newest message is out of reach, so a nudge at the bottom shows no arrow.
  @State private var awayFromLatest = false
  /// Every typing bubble shown so far, keyed by its turn and the reply it stands in for. The
  /// reply that takes a typing bubble's place grows out of it. Only ever added to, so a reply
  /// keeps the same look for its whole life on screen.
  @State private var typingShown: Set<String> = []
  @Namespace private var replyMorph
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
            let turnMessages = replies.messages(in: turn.id)
            let incoming = turnMessages.filter { !$0.outgoing }.map(\.id)
            VStack(spacing: MessagesStyle.bubbleSpacing) {
              ForEach(turnMessages) { message in
                let slot = incoming.firstIndex(of: message.id).map { Self.typingSlot(turn.id, $0) }
                let grows = slot.map { typingShown.contains($0) } ?? false
                ConversationMessageView(
                  message: message, conversationID: conversationID,
                  store: store, parent: replies.parent(of: message),
                  replyCount: replies.count(for: message.id), arrivesWithTurn: true,
                  growsFromTyping: grows,
                  onReply: { composer.reply = $0 }, onOpenThread: { composer.reply = $0 })
                .environment(
                  \.messageMorph, grows ? slot.map { MessageMorph(id: $0, namespace: replyMorph) } : nil)
              }
              if turn.status == "running" {
                // A new typing bubble per reply: the old one becomes the reply that just landed,
                // and the next one grows in beneath it.
                let slot = Self.typingSlot(turn.id, incoming.count)
                TypingIndicator()
                  .environment(\.messageMorph, MessageMorph(id: slot, namespace: replyMorph))
                  .id(slot)
                  .transition(MessagesStyle.typingTransition)
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
        }
        .animation(
          animateMessages ? MessagesStyle.bubbleEntranceAnimation : nil,
          value: messageStructure
        )
        .padding(.horizontal, NessaSpacing.sm).padding(.top, NessaSpacing.sm).padding(
          .bottom, NessaSpacing.md)
        // History can arrive a beat after the thread opens; fade it in rather than pop.
        .animation(reduceMotion ? nil : NessaMotion.standard()) {
          $0.opacity(current == nil ? 0 : 1)
        }
      }.scrollPosition($position, anchor: .bottom)
        .defaultScrollAnchor(.bottom, for: .initialOffset).messagesTrackScroll(
          offset: $scrollOffset
        )
        .messagesScrollEdges().scrollDismissesKeyboard(.interactively)
        // The pin has one owner, `readerScrolled`, and only the reader moves it. The thread's
        // own follow scrolls never do, even when content keeps growing under them and they
        // come to rest short of the bottom.
        .onScrollPhaseChange { _, phase, context in
          switch phase {
          case .interacting:
            readerScrolled = true
            layoutClock.readerDriving = true
          case .idle:
            let gap = Self.scrollRange(context.geometry) - context.geometry.contentOffset.y
            let away = gap > MessagesStyle.followDistance
            let reader = layoutClock.readerDriving
            let ours = Date() < layoutClock.followUntil
            layoutClock.readerDriving = false
            // A drag settles by where it stopped, and so does a scroll the reader asked the
            // system for (a status-bar tap, VoiceOver) once layout is quiet. The system's own
            // scroll after a layout change (the keyboard rising) is not the reader's.
            if reader || (!ours && Date() >= layoutClock.settlesAt) {
              readerScrolled = away
            } else if !readerScrolled && gap > MessagesStyle.pinTolerance && composer.reply == nil {
              // Short by any amount: a follow that rests even a few points up leaves the
              // newest line under the composer.
              follow(animated: followAnimates)
            }
          default:
            break
          }
        }
        .onScrollGeometryChange(for: Bool.self) { geometry in
          Self.scrollRange(geometry) - geometry.contentOffset.y > MessagesStyle.followDistance
        } action: { _, away in
          awayFromLatest = away
        }
        .onScrollGeometryChange(for: CGFloat.self, of: Self.scrollRange) { old, new in
          // Content or container grew under the reader: keep the newest message in place.
          // Shrinking never hides the newest message, so it needs nothing.
          guard new > old else { return }
          layoutClock.settlesAt = Date().addingTimeInterval(MessagesStyle.layoutSettleWindow)
          guard !readerScrolled && composer.reply == nil else { return }
          follow(animated: followAnimates)
        }
        .onChange(of: messageStructure, initial: true) { _, _ in
          for turn in current?.messages ?? [] where turn.status == "running" {
            let replyCount = replies.messages(in: turn.id).filter { !$0.outgoing }.count
            typingShown.insert(Self.typingSlot(turn.id, replyCount))
          }
        }
        .onChange(of: current != nil, initial: true) { _, loaded in
          hasLoadedHistory = loaded
        }
        .onAppear { layoutClock.openedAt = Date() }
        .messagesBar(edge: .bottom) {
          if composer.reply == nil {
            VStack(spacing: NessaSpacing.xs) {
              if store.pendingLoadError != nil { PendingDeliveryUnavailable(store: store) }
              ForEach(store.pendingSubmissions(in: conversationID), id: \.requestID) { command in
                PendingCommandActions(command: command, store: store)
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
            // Floats above the bar rather than sitting in it: a control that changed the bar's
            // height would grow the scroll range and set the thread following itself. It shows
            // only when the reader has left the newest message, the pin's own state.
            .overlay(alignment: .topTrailing) {
              ZStack {
                if readerScrolled && awayFromLatest {
                  MessagesJumpToLatest {
                    readerScrolled = false
                    follow(animated: !reduceMotion, animation: MessagesStyle.jumpToLatestAnimation)
                  }
                  .transition(
                    .scale(scale: MessagesStyle.swapScale, anchor: .trailing)
                      .combined(with: .opacity))
                }
              }
              // Only the arrow animates; the composer beside it keeps its own timing.
              .animation(
                reduceMotion ? nil : NessaMotion.morph, value: readerScrolled && awayFromLatest)
              .padding(.trailing, MessagesStyle.horizontal)
              .alignmentGuide(.top) { $0[.bottom] + NessaSpacing.xs }
            }
          }
        }
    }
    .messagesAmbientGround()
    .messagesBar(edge: .top) {
      ThreadHeader(
        name: name, onBack: { dismiss() }, onDetails: { details = true }, working: working)
        .messagesHeaderGrain()
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
    // Sending brings the reader back to the newest message; the new turn's growth follows.
    readerScrolled = false
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

  /// While the thread is first settling (photos, the composer) the pin is invisible; after
  /// that, growth is a new message, so the list follows it on the message timing.
  private var followAnimates: Bool {
    !reduceMotion && hasLoadedHistory
      && Date() > layoutClock.openedAt.addingTimeInterval(MessagesStyle.openSettleTime)
  }

  private func follow(
    animated: Bool, animation: Animation = MessagesStyle.messageFollowAnimation
  ) {
    layoutClock.followUntil =
      animated ? Date().addingTimeInterval(MessagesStyle.followSettleTime) : .distantPast
    withAnimation(animated ? animation : nil) { position.scrollTo(edge: .bottom) }
  }

  nonisolated private static func typingSlot(_ turn: String, _ reply: Int) -> String {
    "\(turn)#\(reply)"
  }
}

/// What the thread's scroll is doing, read when a scroll comes to rest. A reference, so
/// stamping it on every layout change doesn't re-render the thread.
private final class LayoutSettleClock {
  /// Scrolls that settle before this were started by layout, not by the reader.
  var settlesAt = Date.distantPast
  var openedAt = Date()
  /// The reader's finger has moved the list since it last came to rest.
  var readerDriving = false
  /// Until then, a scroll that comes to rest is the thread's own animated follow. A deadline,
  /// not a flag, because a follow with nowhere to go reports no phases and would leave a flag
  /// set, turning the reader's next status-bar tap into "ours".
  var followUntil = Date.distantPast
}
