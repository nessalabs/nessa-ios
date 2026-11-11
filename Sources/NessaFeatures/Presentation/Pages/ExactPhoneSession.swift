#if os(iOS)
import Combine
import NessaDesignSystem
import SwiftUI
import UIKit

/// State shared by the Contract routes and the iOS controls that need a hosting controller.
@MainActor public final class ExactPhoneSession {
  let dependencies: NessaDependencies
  let messages: MessagesViewModel
  let desktop: DesktopLinkViewModel
  var firstMessages: [String: HomeFirstMessage] = [:]
  var focusChat: String?
  private var subscriptions = Set<AnyCancellable>()

  public init(changed: @escaping (String) -> Void) {
    let dependencies = NessaDependencies.configured()
    self.dependencies = dependencies
    messages = dependencies.makeMessagesViewModel()
    desktop = dependencies.makeDesktopLinkViewModel()
    Publishers.MergeMany([
      messages.$conversations.map { _ in () }.eraseToAnyPublisher(),
      messages.$pendingDeletionIDs.map { _ in () }.eraseToAnyPublisher(),
      messages.$archivedConversations.map { _ in () }.eraseToAnyPublisher(),
      messages.$agentProfiles.map { _ in () }.eraseToAnyPublisher(),
      desktop.$chats.map { _ in () }.eraseToAnyPublisher(),
      desktop.$chatsError.map { _ in () }.eraseToAnyPublisher(),
      desktop.$linked.map { _ in () }.eraseToAnyPublisher(),
    ]).receive(on: RunLoop.main).sink { changed("lists") }.store(in: &subscriptions)
    messages.objectWillChange.merge(with: desktop.objectWillChange)
      .merge(with: Timer.publish(every: 60, on: .main, in: .common).autoconnect().map { _ in () })
      .receive(on: RunLoop.main)
      .compactMap { [weak self] _ in self?.status as NSDictionary? }
      .removeDuplicates()
      .sink { _ in changed("connection") }.store(in: &subscriptions)
    observeAgents(changed).store(in: &subscriptions)
  }

  public var status: [String: Any] {
    let name = desktop.linked?.name ?? "Your Mac"
    let connected = messages.connected
    let label = connected
      ? (desktop.linked != nil && messages.linkedDesktopID == desktop.linked?.id ? name : "Connected")
      : (messages.reconnecting ? "Reconnecting…" : "Not connected")
    let unread = Set(messages.unreadChats).subtracting(messages.archivedChats)
    let unreadChannels = Set(messages.visibleConversations.compactMap { chat in
      unread.contains(chat.id) ? chat.channelId ?? NessaChannel.defaultID : nil
    })
    let channels = messages.channels.enumerated().map { position, channel in
      ["position": position, "id": channel.id, "name": channel.name,
       "unread": unreadChannels.contains(channel.id)] as [String: Any]
    }
    return ["greeting": HomeGreeting.text(at: Date()), "pairingNeeded": !connected && !messages.reconnecting && desktop.linked == nil,
      "waiting": !connected && (messages.reconnecting || desktop.linked != nil),
      "desktopID": desktop.linked?.id.uuidString ?? "", "status": label, "connected": connected, "desktop": name, "canCreate": messages.canCreateChat,
      "working": messages.agentsGlance.count(.working), "channels": channels]
  }

  public func list(_ screen: String, key: String) -> [String: Any] {
    let shared = screen == "shared"
    let chats: [NessaConversation]
    let title: String
    switch screen {
    case "archived": chats = messages.archivedConversations; title = "Archived"
    case "shared": chats = desktop.linked == nil ? [] : desktop.chats; title = desktop.linked?.name ?? "Your Mac"
    case "channel":
      chats = messages.conversations(inChannel: key)
      title = messages.channels.first { $0.id == key }?.name ?? ""
    default: chats = []; title = ""
    }
    let rows = chats.map { chat in
      ["id": chat.id, "title": chat.title ?? (shared ? "Nessa" : messages.agentName(for: chat.id)),
       "preview": chat.running ? "Nessa is working…" : chat.preview ?? "New conversation",
       "time": ConversationRow.timestamp(chat.updatedAtMs)]
    }
    return ["title": title, "rows": rows, "error": shared ? desktop.chatsError ?? "" : ""]
  }

  public func refresh(_ screen: String) async {
    if screen == "archived" { await messages.loadArchived() }
    if screen == "shared" { await desktop.refreshChats() }
    if screen == "channel" {
      do { try await messages.refreshList() }
      catch { messages.error = error.localizedDescription }
    }
  }

  public func unarchive(_ id: String) async { await messages.setArchived(false, conversationID: id) }

  public func retryLink() async { await messages.reconnectLinked() }

  public func createChat() async -> String? {
    let id = await messages.create()
    focusChat = id
    return id
  }

  public func lifecycle(navigate: @escaping (String) -> Void) -> UIViewController {
    UIHostingController(rootView: ExactSessionAlerts(store: messages)
      .modifier(PhoneSessionTasks(dependencies: dependencies, store: messages, linkStore: desktop))
      .onReceive(messages.$deliveryScopeRevision.removeDuplicates().dropFirst()) { [weak self] _ in
        self?.firstMessages.removeAll()
        self?.focusChat = nil
        navigate("/")
      }
      .task { await NessaDependencies.verifyNativePackageIfRequested() })
  }

  public func sharedTranscript(_ id: String, owner: String) async -> [String: Any] {
    let title = desktop.chats.first { $0.id == id }?.title ?? "Chat"
    var result: [String: Any] = ["owner": owner, "chat": id, "title": title, "failed": false, "bubbles": []]
    guard !id.isEmpty, desktop.linked?.id.uuidString == owner else { return result }
    do {
      let view = try await desktop.transcript(id)
      guard desktop.linked?.id.uuidString == owner, !Task.isCancelled else { return result }
      var bubbles = [[String: Any]]()
      for turn in view.messages {
        if !turn.userText.isEmpty {
          bubbles.append(["id": turn.id + ":user", "text": turn.userText, "outgoing": true])
        }
        for fragment in turn.displayBubbles {
          bubbles.append(["id": turn.id + ":reply:" + fragment.id, "text": fragment.text, "outgoing": false])
        }
      }
      result["bubbles"] = bubbles
    } catch {
      result["failed"] = true
    }
    return result
  }
}

private struct ExactSessionAlerts: View {
  @ObservedObject var store: MessagesViewModel
  var body: some View {
    Color.clear.alert("Nessa connection", isPresented: Binding(
      get: { store.error != nil }, set: { if !$0 { store.error = nil } }
    )) {
      Button("OK") { store.error = nil }
    } message: { Text(store.error ?? "") }
  }
}
#endif
