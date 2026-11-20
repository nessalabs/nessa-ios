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
    /// Kept across a retry while the first attempt may still have landed; new once it surely
    /// didn't, since the gateway refuses a request id it has already refused.
    var identity = MessageCommandIdentity()
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
        return
      }
      unmade[conversationID] = nil
    }
    let report = SendFailureReport()
    let accepted: Bool
    if store.pendingCommands.contains(where: { $0.requestID == message.identity.requestID }) {
      // The last attempt may have landed: ask again under the same request, so it can't arrive
      // twice.
      _ = await store.recoverCommand(message.identity.requestID, retry: true, report: report)
      accepted = store.acknowledgedCommands.contains(message.identity.requestID)
    } else {
      accepted = await store.send(
        message.text, attachments: message.attachments, reply: message.reply,
        to: conversationID, identity: message.identity, report: report)
    }
    guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
    if accepted {
      delivered[messages[index].identity.executionID] = id
      messages.remove(at: index)
      return
    }
    // A send that surely didn't land is tried next time as a new request.
    if !store.pendingCommands.contains(where: { $0.requestID == message.identity.requestID }) {
      messages[index].identity = MessageCommandIdentity()
    }
    fail(id, report.words)
  }

  /// Makes a chat started here, or finishes making one whose first try may have landed.
  private func make(
    _ conversationID: String, _ chat: Unmade, store: MessagesViewModel, report: SendFailureReport
  ) async -> Bool {
    if let pending = store.pendingCreations.first(where: { $0.conversationID == conversationID }) {
      return await store.recoverCommand(pending.requestID, retry: true, report: report)
        == conversationID
    }
    return await store.create(channel: chat.channel, conversationID: conversationID, report: report)
      == conversationID
  }

  private func fail(_ id: UUID, _ words: String?) {
    guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
    messages[index].state = .failed(words)
  }
}
