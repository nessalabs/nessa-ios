import Foundation

/// Messages this phone sent that their chat doesn't show yet. A message appears in its chat the
/// moment it is sent, even before the gateway has made the chat, and stays there marked
/// "Couldn't send" if it doesn't get through, so a slow or failed send never holds the composer.
///
/// It owns only what the transcript can't know yet. A message leaves as soon as the gateway
/// takes it; from then on the transcript, and the pending rows for an unconfirmed send, own it.
@MainActor final class OutgoingMessagesViewModel: ObservableObject {
  struct Message: Identifiable, Equatable {
    let id = UUID()
    let conversationID: String
    let text: String
    let attachments: [DraftAttachment]
    let reply: MessageReply?
    /// Kept across a retry unless the gateway refused it, since a refused request id stays
    /// refused; any other failure may have landed and is settled under the same identity.
    var identity = MessageCommandIdentity()
    /// This identity has been sent at least once, so the next try settles it first.
    var attempted = false
    var state = State.sending
  }
  enum State: Equatable {
    case sending
    /// With the reason in plain words, when there is one.
    case failed(String?)
  }
  /// Chats started here that the gateway hasn't made yet, with the channel each goes in.
  private struct Unmade: Equatable { let channel: String? }

  @Published private(set) var messages: [Message] = []
  @Published private var unmade: [String: Unmade] = [:]
  /// The turn each delivered message became, so its row in the chat keeps one identity as the
  /// transcript takes it over and doesn't rise in a second time.
  private(set) var delivered: [String: UUID] = [:]
  /// First messages of chats that couldn't be made and are no longer on screen, handed back to
  /// the composer they came from (keyed by channel, "" for none) so they are never stranded.
  @Published private(set) var returned: [String: HomeFirstMessage] = [:]
  /// Chats open on screen now.
  private var onScreen: Set<String> = []

  /// Starts a chat for `first` and returns its id, so the chat can open straight away; the
  /// chat is made and the message sent behind it.
  func start(_ first: HomeFirstMessage, channel: String?, store: MessagesViewModel) -> String {
    let conversationID = UUID().uuidString.lowercased()
    unmade[conversationID] = Unmade(channel: channel)
    enqueue(
      Message(
        conversationID: conversationID, text: first.text, attachments: first.attachments,
        reply: nil), store: store)
    return conversationID
  }

  func send(
    _ text: String, attachments: [DraftAttachment], reply: MessageReply?, to conversationID: String,
    store: MessagesViewModel
  ) {
    enqueue(
      Message(conversationID: conversationID, text: text, attachments: attachments, reply: reply),
      store: store)
  }

  func retry(_ id: UUID, store: MessagesViewModel) {
    guard let index = messages.firstIndex(where: { $0.id == id }),
      case .failed = messages[index].state
    else { return }
    messages[index].state = .sending
    Task { await deliver(id, store: store) }
  }

  /// The messages to draw in a chat: those whose turn it doesn't show yet.
  func messages(in conversationID: String, shown turns: Set<String>) -> [Message] {
    messages.filter {
      $0.conversationID == conversationID && !turns.contains($0.identity.executionID)
    }
  }

  /// A chat's screen came into view or left it. Leaving a chat that couldn't be made hands its
  /// message back to the composer it came from.
  func onScreen(_ conversationID: String, _ visible: Bool) {
    if visible {
      onScreen.insert(conversationID)
    } else {
      onScreen.remove(conversationID)
      returnIfStranded(conversationID)
    }
  }

  /// Takes back a first message whose chat couldn't be made, for the composer of `channel`.
  func takeReturned(channel: String?) -> HomeFirstMessage? {
    returned.removeValue(forKey: channel ?? "")
  }

  /// The gateway hasn't made this chat yet: nothing else can be sent to it, and it has
  /// nothing to watch.
  func isUnmade(_ conversationID: String) -> Bool { unmade[conversationID] != nil }

  /// A message is in flight to this chat; the composer waits for it, as the gateway takes one
  /// send at a time.
  func isSending(in conversationID: String) -> Bool {
    messages.contains { $0.conversationID == conversationID && $0.state == .sending }
  }

  private func enqueue(_ message: Message, store: MessagesViewModel) {
    messages.append(message)
    Task { await deliver(message.id, store: store) }
  }

  private func deliver(_ id: UUID, store: MessagesViewModel) async {
    guard let message = messages.first(where: { $0.id == id }) else { return }
    let conversationID = message.conversationID
    if let chat = unmade[conversationID] {
      let report = SendFailureReport()
      guard await make(conversationID, chat, store: store, report: report) else {
        fail(id, report.words ?? "This chat couldn’t be started.")
        returnIfStranded(conversationID)
        return
      }
      unmade[conversationID] = nil
    }
    let report = SendFailureReport()
    let accepted =
      message.attempted
      ? await store.retrySend(
        message.text, attachments: message.attachments, reply: message.reply,
        to: conversationID, identity: message.identity, report: report)
      : await store.send(
        message.text, attachments: message.attachments, reply: message.reply,
        to: conversationID, identity: message.identity, report: report)
    guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
    if accepted {
      delivered[messages[index].identity.executionID] = id
      messages.remove(at: index)
      return
    }
    // Only a refusal spends the request: anything else may have landed, so the next try
    // settles this one first rather than sending a second.
    if report.refused {
      messages[index].identity = MessageCommandIdentity()
      messages[index].attempted = false
    } else {
      messages[index].attempted = true
    }
    fail(id, report.words)
  }

  /// Makes a chat started here, or finishes making one whose first try may have landed.
  private func make(
    _ conversationID: String, _ chat: Unmade, store: MessagesViewModel, report: SendFailureReport
  ) async -> Bool {
    // An earlier try that landed after all: the chat is already listed.
    if store.views[conversationID] != nil
      || store.conversations.contains(where: { $0.id == conversationID })
    {
      return true
    }
    if let pending = store.pendingCreations.first(where: { $0.conversationID == conversationID }) {
      return await store.recoverCommand(pending.requestID, retry: true, report: report)
        == conversationID
    }
    return await store.create(channel: chat.channel, conversationID: conversationID, report: report)
      == conversationID
  }

  /// A chat that couldn't be made, with nobody looking at it, exists nowhere else: its message
  /// goes back to the composer it came from rather than being lost with it.
  private func returnIfStranded(_ conversationID: String) {
    guard let chat = unmade[conversationID], !onScreen.contains(conversationID),
      let message = messages.first(where: { $0.conversationID == conversationID }),
      case .failed = message.state
    else { return }
    messages.removeAll { $0.conversationID == conversationID }
    unmade[conversationID] = nil
    returned[chat.channel ?? ""] = HomeFirstMessage(
      text: message.text, attachments: message.attachments)
  }

  private func fail(_ id: UUID, _ words: String?) {
    guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
    messages[index].state = .failed(words)
  }
}
