import Combine
import Foundation

/// A completion owns the captured revision, never whatever happens to be typed later.
@MainActor final class ComposerDraftViewModel: ObservableObject {
  struct Attempt: Sendable {
    let identity: MessageCommandIdentity
    let revision: UInt64
    let scope: Int
    let text: String
    let attachments: [DraftAttachment]
    let reply: MessageReply?
  }
  @Published var text = "" { didSet { if text != oldValue { revision &+= 1 } } }
  @Published var attachments: [DraftAttachment] = [] {
    didSet { if attachments != oldValue { revision &+= 1 } }
  }
  @Published var reply: MessageReply? { didSet { if reply != oldValue { revision &+= 1 } } }
  private var revision: UInt64 = 0
  private var owned: [String: (revision: UInt64, scope: Int)] = [:]
  private var active: Set<String> = []
  func begin(scope: Int) -> Attempt {
    let identity = MessageCommandIdentity()
    owned[identity.requestID] = (revision, scope)
    active.insert(identity.requestID)
    return Attempt(
      identity: identity, revision: revision, scope: scope,
      text: text, attachments: attachments, reply: reply)
  }
  /// Both phone renderers submit the captured revision through the same durable send path.
  func submit(in conversationID: String, store: MessagesViewModel) {
    let captured = begin(scope: store.deliveryScopeRevision)
    Task {
      let accepted = await store.send(
        captured.text, attachments: captured.attachments,
        reply: captured.reply, to: conversationID, identity: captured.identity)
      if accepted {
        self.accept([captured.identity.requestID], scope: store.deliveryScopeRevision)
      }
      self.accept(store.acknowledgedCommands, scope: store.deliveryScopeRevision)
      let knownQueue = store.connected && store.pendingLoadError == nil
      let pending = store.pendingCommands.contains { $0.requestID == captured.identity.requestID }
      self.finished(captured.identity.requestID, keepPending: !knownQueue || pending)
    }
  }
  func finished(_ requestID: String, keepPending: Bool) {
    active.remove(requestID)
    if !keepPending { owned.removeValue(forKey: requestID) }
  }
  func retainPending(_ ids: Set<String>) {
    owned = owned.filter { ids.contains($0.key) || active.contains($0.key) }
  }
  func accept(_ identities: Set<String>, scope: Int) {
    for id in identities {
      guard let original = owned.removeValue(forKey: id) else { continue }
      guard original.scope == scope, original.revision == revision else { continue }
      text = ""
      attachments = []
    }
  }
}
