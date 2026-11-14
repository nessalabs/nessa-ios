#if os(iOS)
import Combine
import UIKit

/// The transcript and the reply editor must refer to the same captured draft and delivery scope.
@MainActor struct ExactChatComposerHandle {
  let draft: ComposerDraftViewModel
  let autoFocus: Bool
  let started: () -> Void
  let sent: () -> Void
}

private struct ComposerAddress: Hashable {
  let visit: String
  let screen: String
  let key: String
}

/// Owns drafts for mounted Contract editors. Scope changes invalidate every in-flight edit,
/// picker and recovery operation, even when the replacement gateway reuses the same chat IDs.
@MainActor public final class ExactComposers {
  private let phone: ExactPhoneSession
  private let threads: ExactThreads
  private let changed: () -> Void
  private var editors: [ComposerAddress: ExactComposerDraft] = [:]
  private var scopeObserver: AnyCancellable?

  public init(phone: ExactPhoneSession, threads: ExactThreads, changed: @escaping () -> Void) {
    self.phone = phone
    self.threads = threads
    self.changed = changed
    scopeObserver = phone.messages.$deliveryScopeRevision.removeDuplicates().dropFirst().receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.invalidate() }
  }

  private func invalidate() {
    for (address, editor) in editors where !editor.valid {
      editor.finish()
      editors.removeValue(forKey: address)
    }
    changed()
  }

  public func present(visit: String, screen: String, key: String, navigate: @escaping (String) -> Void)
    -> UIViewController
  {
    let address = ComposerAddress(visit: visit, screen: screen, key: key)
    let editor = ExactComposerDraft(phone: phone, visit: visit, screen: screen, key: key,
      thread: screen == "chat" ? threads.composerHandle(key) : nil, changed: changed, navigate: navigate)
    editors[address]?.finish()
    editors[address] = editor
    let anchor = ExactComposerAnchor(editor: editor) { [weak self, weak editor] in
      guard let self, let editor, self.editors[address] === editor else { return }
      editor.finish()
      self.editors.removeValue(forKey: address)
      self.changed()
    }
    editor.presenter = anchor
    changed()
    return anchor
  }

  public func snapshot(visit: String, screen: String, key: String) -> [String: Any]? {
    guard let editor = editors[ComposerAddress(visit: visit, screen: screen, key: key)],
      editor.valid else { return ["scope": String(phone.messages.deliveryScopeRevision)] }
    return editor.snapshot
  }

  public func photo(token: String, attachment id: String, preview: Bool) -> UIView {
    guard let editor = editors.values.first(where: { $0.token == token && $0.valid }),
      let fileID = UUID(uuidString: id) else { return UIView() }
    return ExactDraftPhoto(editor: editor, id: fileID, preview: preview)
  }

  private func editor(for request: [String: Any]) -> ExactComposerDraft? {
    guard let visit = request["visit"] as? String, let screen = request["screen"] as? String,
      let key = request["key"] as? String, let token = request["token"] as? String,
      let editor = editors[ComposerAddress(visit: visit, screen: screen, key: key)],
      editor.valid, editor.token == token else { return nil }
    return editor
  }

  public func edit(_ request: [String: Any]) {
    guard let editor = editor(for: request), let text = request["value"] as? String,
      let next = request["sequence"] as? Int else { return }
    editor.edit(text, sequence: next)
  }

  public func perform(_ request: [String: Any]) async {
    guard let editor = editor(for: request), let action = request["action"] as? String else { return }
    await editor.perform(action, value: request["value"] as? String ?? "",
      sequence: request["sequence"] as? Int ?? 0)
  }
}

@MainActor final class ExactComposerDraft {
  let phone: ExactPhoneSession
  let visit: String
  let screen: String
  let key: String
  let token = UUID().uuidString
  let scope: Int
  let thread: ExactChatComposerHandle?
  let draft: ComposerDraftViewModel
  let dictation: DictationViewModel
  let changed: () -> Void
  private let navigate: (String) -> Void
  weak var presenter: ExactComposerAnchor?
  private var subscriptions = Set<AnyCancellable>()
  private var watch: Task<Void, Never>?
  private var preparation: Task<Void, Never>?
  private var preparationID: UUID?
  private var takingFirst = false
  private var visible = false
  private var starting = false
  private var submittedSequence: Int?
  private var closed = false
  private(set) var sequence = 0
  private var pickerError: String?
  var valid: Bool { !closed && scope == phone.messages.deliveryScopeRevision }
  private var store: MessagesViewModel { phone.messages }
  private var replying: Bool { draft.reply != nil }
  private var sending: Bool { thread == nil ? starting || store.busy : store.sending }
  private var connected: Bool { store.connected }
  private var channel: NessaChannel? { screen == "channel" ? store.channels.first { $0.id == key } : nil }
  private var canSubmit: Bool {
    if thread != nil { return store.canSubmit(in: key) }
    return store.canCreateChat && !starting && (screen != "channel" || channel != nil)
  }
  private var canAttach: Bool { !sending && !dictation.active && preparationID == nil }
  private var runningTurn: String? {
    guard thread != nil, !replying else { return nil }
    return store.views[key]?.messages.last { $0.status == "running" }?.id
  }

  init(phone: ExactPhoneSession, visit: String, screen: String, key: String,
    thread: ExactChatComposerHandle?, changed: @escaping () -> Void, navigate: @escaping (String) -> Void) {
    self.phone = phone
    self.visit = visit
    self.screen = screen
    self.key = key
    self.thread = thread
    self.changed = changed
    self.navigate = navigate
    scope = phone.messages.deliveryScopeRevision
    draft = thread?.draft ?? ComposerDraftViewModel()
    dictation = phone.dependencies.makeDictationViewModel()
    Publishers.Merge3(store.objectWillChange, draft.objectWillChange, dictation.objectWillChange)
      .receive(on: RunLoop.main).throttle(for: .milliseconds(12), scheduler: RunLoop.main, latest: true)
      .sink { [weak self] in if self?.valid == true { self?.changed() } }.store(in: &subscriptions)
    dictation.$transcriptRevision.dropFirst().sink { [weak self] _ in
      guard let self, self.valid, !self.dictation.transcript.isEmpty else { return }
      self.draft.text = self.dictation.transcript
    }.store(in: &subscriptions)
    if thread != nil {
      store.$acknowledgedCommands.sink { [weak self] ids in
        guard let self, self.valid else { return }
        self.draft.accept(ids, scope: self.scope)
      }.store(in: &subscriptions)
      store.$pendingCommands.sink { [weak self] commands in
        guard let self, self.valid, self.store.connected, self.store.pendingLoadError == nil else { return }
        self.draft.retainPending(Set(commands.map(\.requestID)))
      }.store(in: &subscriptions)
      store.$connectionRevision.removeDuplicates().dropFirst().receive(on: RunLoop.main)
        .sink { [weak self] _ in self?.restartWatch() }.store(in: &subscriptions)
    }
  }

  func appeared() {
    guard valid, !visible else { return }
    visible = true
    restartWatch()
    if !takingFirst { takingFirst = true; thread?.started() }
    changed()
  }

  func disappeared() {
    visible = false
    watch?.cancel()
    watch = nil
    cancelPreparation()
    dictation.cancel()
  }

  func finish() {
    closed = true
    disappeared()
    subscriptions.removeAll()
  }

  private func restartWatch() {
    watch?.cancel()
    guard visible, valid, thread != nil else { return }
    let store = self.store, chat = key
    watch = Task { await store.watchConversation(chat) }
  }

  private var recovery: [[String: Any]] {
    guard thread != nil else { return [] }
    var rows: [[String: Any]] = []
    if store.pendingLoadError != nil {
      rows.append(["id": "reconnect", "key": "", "title": "Pending deliveries unavailable",
        "check": false, "retry": false, "reconnect": true, "busy": false, "enabled": true])
    }
    if !replying {
      for delivery in store.phoneDeliveries(in: key) {
        let title: String
        switch delivery.outcome {
        case .unknown: title = "Delivery not confirmed"
        case .failed: title = "Message not sent"
        default: title = "Message"
        }
        rows.append(["id": "delivery:" + delivery.commandID, "key": delivery.commandID, "title": title,
          "check": false, "retry": delivery.outcome.admitsRetry, "reconnect": false, "busy": false,
          "enabled": connected && !store.accessRevoked])
      }
    }
    for command in store.pendingSubmissions(in: key) {
      let busy = store.checkingCommands.contains(command.requestID)
      rows.append(["id": "pending:" + command.requestID, "key": command.requestID,
        "title": "Pending message", "check": true, "retry": true, "reconnect": false,
        "busy": busy, "enabled": connected && !busy])
    }
    return rows
  }

  var snapshot: [String: Any] {
    let name = thread != nil ? store.agentName(for: key)
      : channel?.name ?? (store.agentProfiles.count == 1 ? store.agentProfiles[0].displayName : "Nessa")
    let files = draft.attachments.map { attachment in
      ["id": attachment.id.uuidString, "name": attachment.name, "image": attachment.isImage] as [String: Any]
    }
    return ["token": token, "scope": String(scope), "visit": visit, "screen": screen, "key": key, "text": draft.text, "seq": sequence,
      "placeholder": replying ? "Reply" : "Message " + name + (screen == "home" ? " or hold to talk" : ""),
      "reason": thread != nil ? store.submissionUnavailableReason(in: key) ?? "" : "",
      "role": draft.reply?.id ?? "", "autoFocus": replying || thread?.autoFocus == true,
      "sendable": connected && canSubmit && !sending && preparationID == nil && !dictation.active,
      "attachable": canAttach, "sending": sending, "preparing": preparationID != nil,
      "listening": dictation.active, "finishing": dictation.state == .finishing,
      "running": runningTurn ?? "", "canStop": connected && !store.accessRevoked,
      "errorTitle": pickerError == nil ? "Dictation" : "Attachment", "error": pickerError ?? dictation.error ?? "",
      "files": files, "recovery": recovery]
  }

  /// Commands validate both the captured session and the live action's preconditions.
  func perform(_ action: String, value: String, sequence next: Int) async {
    guard valid else { return }
    switch action {
    case "edit":
      edit(value, sequence: next)
    case "send":
      guard next >= sequence, submittedSequence != next, !sending, !dictation.active, preparationID == nil, connected, canSubmit,
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !draft.attachments.isEmpty else { return }
      submittedSequence = next
      sequence = next
      draft.text = value
      UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.7)
      if let thread { thread.sent() } else { await create() }
    case "dictate":
      guard !sending, preparationID == nil, dictation.state != .finishing else { return }
      dictation.toggle()
    case "stop":
      guard value == runningTurn, connected, !store.accessRevoked else { return }
      await store.stopTurn(value, in: key)
    case "remove":
      guard !sending, let id = UUID(uuidString: value) else { return }
      draft.attachments.removeAll { $0.id == id }
    case "camera", "photos", "files":
      guard canAttach else { return }
      presenter?.choose(action, policy: store.attachmentPolicy, count: draft.attachments.count)
    case "clearError": pickerError = nil; dictation.error = nil
    case "reconnect":
      guard thread != nil, store.pendingLoadError != nil else { return }
      await store.reconnectDeliveryState()
    case "check", "retry":
      guard thread != nil, connected, !store.checkingCommands.contains(value),
        store.pendingSubmissions(in: key).contains(where: { $0.requestID == value }) else { return }
      _ = await store.recoverCommand(value, retry: action == "retry")
    case "retryDelivery":
      guard thread != nil, !replying, connected, !store.accessRevoked,
        store.phoneDeliveries(in: key).contains(where: { $0.commandID == value && $0.outcome.admitsRetry })
        else { return }
      await store.retryPhoneDelivery(value)
    default: return
    }
    if valid { changed() }
  }

  func edit(_ value: String, sequence next: Int) {
    guard valid, next > sequence, !dictation.active else { return }
    sequence = next
    draft.text = value
    changed()
  }

  private func create() async {
    starting = true
    changed()
    defer { starting = false; if valid { changed() } }
    let first = HomeFirstMessage(text: draft.text, attachments: draft.attachments)
    let channelID = channel.flatMap { $0.isDefault ? nil : $0.channelId }
    guard let id = await store.create(channel: channelID), valid else { return }
    first.consume(from: &draft.text, attachments: &draft.attachments)
    phone.firstMessages[id] = first
    if visible { navigate("/chat/" + (id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")) }
  }

  func failPicker(_ message: String) { if valid { pickerError = message; changed() } }
  func cancelPreparation() {
    preparationID = nil
    preparation?.cancel()
    preparation = nil
  }

  func prepare(_ items: [@MainActor () async throws -> DraftAttachment]) {
    guard valid, !items.isEmpty else { return }
    cancelPreparation()
    let id = UUID()
    preparationID = id
    changed()
    preparation = Task { [weak self] in
      guard let self else { return }
      for load in items {
        do {
          let file = try await load()
          guard self.valid, !Task.isCancelled, !self.sending, self.preparationID == id else { return }
          try self.store.attachmentPolicy.validate(self.draft.attachments + [file])
          self.draft.attachments.append(file)
        } catch {
          guard self.valid, !Task.isCancelled, self.preparationID == id else { return }
          self.failPicker(error.localizedDescription)
        }
      }
      if self.preparationID == id {
        self.preparationID = nil
        self.preparation = nil
        self.changed()
      }
    }
  }
}
#endif
