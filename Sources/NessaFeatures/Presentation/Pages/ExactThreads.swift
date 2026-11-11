#if os(iOS)
import Combine
import NessaDesignSystem
import SwiftUI
import UIKit

/// Live view state scoped to a mounted Exact thread and its delivery identity. The store
/// remains the only owner of permission answers, durable commands, and transcript reads.
@MainActor public final class ExactThreads {
  private let phone: ExactPhoneSession
  private let changed: () -> Void
  private let threads = NSMapTable<NSString, ExactThreadState>.strongToWeakObjects()

  public init(phone: ExactPhoneSession, changed: @escaping () -> Void) {
    self.phone = phone
    self.changed = changed
  }

  private func state(for id: String) -> ExactThreadState {
    if let state = threads.object(forKey: id as NSString),
      state.scope == phone.messages.deliveryScopeRevision { return state }
    let state = ExactThreadState(phone: phone, id: id, changed: changed)
    threads.setObject(state, forKey: id as NSString)
    return state
  }

  public func snapshot(_ id: String) -> [String: Any] {
    state(for: id).snapshot()
  }

  public func details(_ chat: String) -> [String: Any] { phone.agentDetails(for: chat) }

  public func command(_ command: String, chat: String, review: String, option: String) async {
    // A late button from a popped route or a former connection has no authority.
    guard let state = threads.object(forKey: chat as NSString),
      state.scope == phone.messages.deliveryScopeRevision else { return }
    switch command {
    case "closeMenu": state.context.selection = nil
    case "closeReplies": state.composer.reply = nil
    case "answer":
      guard phone.messages.connected, phone.messages.conversationAuthorityReady,
        let offered = phone.messages.views[chat]?.permissions.first(where: {
          ExactPermissionAction.option(option, stamp: review, review: $0,
            scope: phone.messages.deliveryScopeRevision, connection: phone.messages.connectionRevision) != nil
        }), let choice = ExactPermissionAction.option(option, stamp: review, review: offered,
          scope: phone.messages.deliveryScopeRevision, connection: phone.messages.connectionRevision) else { return }
      await phone.messages.answer(offered, option: choice, in: chat)
    default: break
    }
  }

  public func part(_ part: String, chat: String, item: String, size: @escaping (CGSize) -> Void)
    -> UIViewController
  {
    let state = state(for: chat)
    let content = ExactThreadPart(part: part, item: item, state: state, store: phone.messages,
      composer: state.composer, report: size)
    let controller = UIHostingController(rootView: content)
    controller.safeAreaRegions = []
    controller.view.backgroundColor = .clear
    return controller
  }
}

@MainActor private final class ExactThreadState: ObservableObject {
  let phone: ExactPhoneSession
  let chat: String
  let scope: Int
  let dictation: DictationViewModel
  let context = MessageContextController()
  let composer = ComposerDraftViewModel()
  let autoFocus: Bool
  private(set) var sendSequence = 0
  private let changed: () -> Void
  private var subscriptions = Set<AnyCancellable>()

  init(phone: ExactPhoneSession, id: String, changed: @escaping () -> Void) {
    self.phone = phone
    chat = id
    scope = phone.messages.deliveryScopeRevision
    autoFocus = phone.focusChat == id
    dictation = phone.dependencies.makeDictationViewModel()
    self.changed = changed
    Publishers.Merge3(phone.messages.objectWillChange.map { _ in () },
      composer.$reply.removeDuplicates().dropFirst().map { _ in () },
      context.$selection.map { $0 != nil }.removeDuplicates().dropFirst().map { _ in () })
      .receive(on: RunLoop.main)
      .throttle(for: .milliseconds(16), scheduler: RunLoop.main, latest: true)
      .sink { [weak self] in self?.changed() }.store(in: &subscriptions)
  }

  func takeFirstMessage() {
    guard scope == phone.messages.deliveryScopeRevision else { return }
    if phone.focusChat == chat { phone.focusChat = nil }
    guard let first = phone.firstMessages.removeValue(forKey: chat) else { return }
    composer.text = first.text
    composer.attachments = first.attachments
    send()
  }

  func send() {
    guard scope == phone.messages.deliveryScopeRevision else { return }
    sendSequence += 1
    changed()
    composer.submit(in: chat, store: phone.messages)
  }

  func snapshot() -> [String: Any] {
    let store = phone.messages
    let view = store.views[chat]
    let projection = store.replyProjection(in: chat)
    let turns = view?.messages ?? []
    let selected = composer.reply
    var rows: [[String: Any]] = []
    var reviews = view?.permissions ?? []
    if let selected {
      let root = projection.root(for: selected.id)
      let messages = (root.map { [$0] } ?? []) + (root.map { projection.replies(to: $0.id) } ?? [])
      if root == nil {
        rows.append(["kind": "quote", "id": selected.id, "text": selected.text, "first": false])
      }
      rows += messages.map { ["kind": "message", "id": $0.id, "text": "", "first": false] as [String: Any] }
      if let last = messages.last, last.id != root?.id,
        turns.first(where: { $0.id == last.turnID })?.awaitsReply == true {
        rows.append(["kind": "typing", "id": last.turnID + ":typing", "text": "", "first": false])
      }
      let turnIDs = Set(messages.map(\.turnID))
      for turn in turns where turnIDs.contains(turn.id) {
        if let error = turn.error { rows.append(["kind": "error", "id": turn.id + ":error", "text": error, "first": false]) }
      }
      reviews = reviews.filter { turnIDs.contains($0.executionId) }
    } else {
      for turn in turns {
        let firstIndex = rows.count
        rows += projection.messages(in: turn.id).map { ["kind": "message", "id": $0.id, "text": "", "first": false] as [String: Any] }
        if turn.awaitsReply { rows.append(["kind": "typing", "id": turn.id + ":typing", "text": "", "first": false]) }
        if let error = turn.error { rows.append(["kind": "error", "id": turn.id + ":error", "text": error, "first": false]) }
        if firstIndex > 0 && firstIndex < rows.count { rows[firstIndex]["first"] = true }
      }
    }
    let cards = reviews.map { review -> [String: Any] in
      let ordered = review.options.filter { $0.effect != "allow" } + review.options.filter { $0.effect == "allow" }
      let primary = review.options.first { $0.effect == "allow" }?.id
      return ["id": review.review, "title": review.title, "arguments": review.argumentsJson,
        "stamp": ExactPermissionAction.stamp(review, scope: store.deliveryScopeRevision, connection: store.connectionRevision),
        "options": ordered.map { ["id": $0.id, "label": $0.label, "primary": $0.id == primary] as [String: Any] }]
    }
    return ["chat": chat, "name": store.agentName(for: chat), "rows": rows, "reviews": cards,
      "connected": store.connected, "working": turns.contains { $0.status == "running" },
      "empty": view?.messages.isEmpty == true && selected == nil,
      "recent": view?.truncated == true && selected == nil,
      "error": selected == nil ? view?.interactionViewError ?? "" : "",
      "reply": selected?.id ?? "", "menu": context.selection != nil, "sent": sendSequence]
  }
}

private struct ExactThreadPart: View {
  let part: String
  let item: String
  @ObservedObject var state: ExactThreadState
  @ObservedObject var store: MessagesViewModel
  @ObservedObject var composer: ComposerDraftViewModel
  let report: (CGSize) -> Void

  var body: some View {
    Group {
      if state.scope != store.deliveryScopeRevision {
        Color.clear
      } else if part == "context" {
        MessageContextOverlay(controller: state.context)
      } else {
        content
          .frame(maxWidth: .infinity)
          .fixedSize(horizontal: false, vertical: true)
          .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            if size.width > 0 && size.height > 0 { report(size) }
          }
          .frame(maxHeight: .infinity, alignment: .top)
      }
    }
    .environment(\.messageContext, state.context)
    .preferredColorScheme(.dark)
    .foregroundStyle(MessagesStyle.foreground)
    .tint(MessagesStyle.foreground)
  }

  @ViewBuilder private var content: some View {
    switch part {
    case "message":
      let replies = store.replyProjection(in: state.chat)
      if let message = replies.message(item) {
        ConversationMessageView(message: message, conversationID: state.chat, store: store,
          parent: composer.reply == nil ? replies.parent(of: message) : nil,
          replyCount: composer.reply == nil ? replies.count(for: item) : 0,
          arrivesWithTurn: true, onReply: { composer.reply = $0 }, onOpenThread: { composer.reply = $0 })
      }
    case "artifact":
      if let artifact = ConversationArtifact.collect(from: store.views[state.chat]?.messages ?? [])
        .first(where: { $0.id == item }), case .image(let image) = artifact.content {
        PhotoAttachment(id: artifact.id) { await store.imageData(for: image) }
      }
    case "avatar", "hero":
      AgentAvatar(seed: state.chat, size: part == "hero" ? AgentDetailsStyle.heroAvatar : MessagesStyle.titleAvatar,
        working: store.views[state.chat]?.messages.contains { $0.status == "running" } == true)
    case "typing": TypingIndicator()
    case "composer":
      editor
        .task(id: store.connectionRevision) { await store.watchConversation(state.chat) }
        .task { state.takeFirstMessage() }
        .onChange(of: store.acknowledgedCommands) { _, ids in
          composer.accept(ids, scope: store.deliveryScopeRevision)
        }
        .onChange(of: store.pendingCommands) { _, commands in
          if store.connected && store.pendingLoadError == nil {
            composer.retainPending(Set(commands.map(\.requestID)))
          }
        }
    default: EmptyView()
    }
  }

  private var editor: some View {
    let running = store.views[state.chat]?.messages.last { $0.status == "running" }?.id
    let replying = composer.reply != nil
    return VStack(spacing: NessaSpacing.xs) {
      if store.pendingLoadError != nil { PendingDeliveryUnavailable(store: store) }
      if !replying {
        ForEach(store.phoneDeliveries(in: state.chat)) { PhoneDeliveryRow(delivery: $0, store: store) }
      }
      ForEach(store.pendingSubmissions(in: state.chat), id: \.requestID) {
        PendingCommandActions(command: $0, store: store)
      }
      MessageComposer(draft: $composer.text, reply: $composer.reply, attachments: $composer.attachments,
        recipient: store.agentName(for: state.chat), dictation: state.dictation, sending: store.sending,
        connected: store.connected, attachmentPolicy: store.attachmentPolicy,
        submissionAllowed: store.canSubmit(in: state.chat),
        submissionUnavailableReason: store.submissionUnavailableReason(in: state.chat),
        placeholder: replying ? "Reply" : nil, autoFocus: replying || state.autoFocus,
        working: !replying && running != nil,
        onStop: running.map { turn in { Task { await store.stopTurn(turn, in: state.chat) } } },
        stopAvailable: store.connected && !store.accessRevoked, onSend: state.send)
        .id(replying)
    }
  }
}
#endif
