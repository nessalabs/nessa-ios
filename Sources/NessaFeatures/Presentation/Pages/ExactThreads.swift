#if os(iOS)
import Combine
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

  func composerHandle(_ id: String) -> ExactChatComposerHandle {
    let state = state(for: id)
    return ExactChatComposerHandle(draft: state.composer, autoFocus: state.autoFocus,
      started: { state.takeFirstMessage() },
      sent: { state.send() })
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
    case "openReplies", "reactMessage", "removeReaction":
      guard let message = phone.messages.replyProjection(in: chat).message(review) else { return }
      if command == "openReplies" {
        guard Int(option) == state.scope else { return }
        state.composer.reply = message.reply
      } else if let glyph = ExactReactionAction.glyph(option, scope: state.scope),
        command != "removeReaction" || phone.messages.reaction(message: message.id, in: chat) == glyph {
        phone.messages.react(glyph, message: message.id, in: chat)
      }
    case "closeReplies":
      guard Int(option) == state.scope, state.composer.reply?.id == review else { return }
      state.composer.reply = nil
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

}

@MainActor private final class ExactThreadState: ObservableObject {
  let phone: ExactPhoneSession
  let chat: String
  let scope: Int
  let dictation: DictationViewModel
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
    phone.messages.objectWillChange.map { _ in () }
      .merge(with: composer.$reply.removeDuplicates().dropFirst().map { _ in () })
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
    func messageRow(_ message: ConversationMessage) -> [String: Any] {
      ExactBubbleProjection.message(message,
        parent: selected == nil ? projection.parent(of: message) : nil,
        replies: selected == nil ? projection.count(for: message.id) : 0,
        reaction: store.reaction(message: message.id, in: chat), scope: scope)
    }
    func notice(_ kind: String, _ id: String, _ text: String = "") -> [String: Any] {
      ExactBubbleProjection.notice(kind, id: id, text: text, scope: scope)
    }
    var reviews = view?.permissions ?? []
    if let selected {
      let root = projection.root(for: selected.id)
      let messages = (root.map { [$0] } ?? []) + (root.map { projection.replies(to: $0.id) } ?? [])
      if root == nil {
        rows.append(notice("quote", selected.id, selected.text))
      }
      rows += messages.map(messageRow)
      if let last = messages.last, last.id != root?.id,
        turns.first(where: { $0.id == last.turnID })?.awaitsReply == true {
        rows.append(notice("typing", last.turnID + ":typing"))
      }
      let turnIDs = Set(messages.map(\.turnID))
      for turn in turns where turnIDs.contains(turn.id) {
        if let error = turn.error { rows.append(notice("error", turn.id + ":error", error)) }
      }
      reviews = reviews.filter { turnIDs.contains($0.executionId) }
    } else {
      for turn in turns {
        let firstIndex = rows.count
        rows += projection.messages(in: turn.id).map(messageRow)
        if turn.awaitsReply { rows.append(notice("typing", turn.id + ":typing")) }
        if let error = turn.error { rows.append(notice("error", turn.id + ":error", error)) }
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
    return ["chat": chat, "scope": scope, "name": store.agentName(for: chat), "rows": rows, "reviews": cards,
      "connected": store.connected, "working": turns.contains { $0.status == "running" },
      "empty": view?.messages.isEmpty == true && selected == nil,
      "recent": view?.truncated == true && selected == nil,
      "error": selected == nil ? view?.interactionViewError ?? "" : "",
      "reply": selected?.id ?? "", "sent": sendSequence]
  }
}

#endif
