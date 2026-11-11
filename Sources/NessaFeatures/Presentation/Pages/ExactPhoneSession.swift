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
      messages.$archivedConversations.map { _ in () }.eraseToAnyPublisher(),
      messages.$agentProfiles.map { _ in () }.eraseToAnyPublisher(),
      desktop.$chats.map { _ in () }.eraseToAnyPublisher(),
      desktop.$chatsError.map { _ in () }.eraseToAnyPublisher(),
      desktop.$linked.map { _ in () }.eraseToAnyPublisher(),
    ]).receive(on: RunLoop.main).sink { changed("lists") }.store(in: &subscriptions)
    messages.objectWillChange.merge(with: desktop.objectWillChange)
      .receive(on: RunLoop.main)
      .compactMap { [weak self] _ in self?.status as NSDictionary? }
      .removeDuplicates()
      .sink { _ in changed("connection") }.store(in: &subscriptions)
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
    let channels = messages.channels.map { channel in
      ["id": channel.id, "name": channel.name,
       "unread": unreadChannels.contains(channel.id)] as [String: Any]
    }
    return ["status": label, "connected": connected, "desktop": name, "canCreate": messages.canCreateChat,
      "working": messages.agentsGlance.count(.working), "channels": channels]
  }

  public func list(_ screen: String) -> [String: Any] {
    let archived = screen == "archived"
    let chats = archived ? messages.archivedConversations : (desktop.linked == nil ? [] : desktop.chats)
    let rows = chats.map { chat in
      ["id": chat.id, "title": chat.title ?? (archived ? messages.agentName(for: chat.id) : "Nessa"),
       "preview": chat.running ? "Nessa is working…" : chat.preview ?? "New conversation",
       "time": ConversationRow.timestamp(chat.updatedAtMs)]
    }
    return ["rows": rows, "error": archived ? "" : desktop.chatsError ?? ""]
  }

  public func refresh(_ screen: String) async {
    if screen == "archived" { await messages.loadArchived() }
    if screen == "shared" { await desktop.refreshChats() }
  }

  public func unarchive(_ id: String) async { await messages.setArchived(false, conversationID: id) }

  public func avatar(_ id: String) -> UIViewController {
    let controller = UIHostingController(rootView: AgentAvatar(seed: id, size: MessagesStyle.rowAvatar))
    controller.view.backgroundColor = .clear
    controller.view.isUserInteractionEnabled = false
    return controller
  }

  public func createChat() async -> String? {
    let id = await messages.create()
    focusChat = id
    return id
  }

  public func lifecycle(navigate: @escaping (String) -> Void) -> UIViewController {
    UIHostingController(rootView: Color.clear
      .modifier(PhoneSessionTasks(dependencies: dependencies, store: messages, linkStore: desktop))
      .onReceive(messages.$deliveryScopeRevision.removeDuplicates().dropFirst()) { [weak self] _ in
        self?.firstMessages.removeAll()
        self?.focusChat = nil
        navigate("/")
      }
      .task { await NessaDependencies.verifyNativePackageIfRequested() })
  }

  public func page(_ name: String, identifier: String, navigate: @escaping (String) -> Void)
    -> UIViewController
  {
    let page = ExactPhonePage(session: self, screen: name, identifier: identifier, navigate: navigate)
    return UIHostingController(rootView: page)
  }
}

private struct ExactPhonePage: View {
  let session: ExactPhoneSession
  let screen: String
  let identifier: String
  let navigate: (String) -> Void
  @ObservedObject var store: MessagesViewModel
  @ObservedObject var desktop: DesktopLinkViewModel
  @StateObject private var dictation: DictationViewModel
  @AppStorage("nessaGatewayAddress") private var address = "ws://127.0.0.1:7420/session"
  @AppStorage("nessaSurfaceInstance") private var instance = ""
  @State private var pairing = false

  init(session: ExactPhoneSession, screen: String, identifier: String, navigate: @escaping (String) -> Void) {
    self.session = session
    self.screen = screen
    self.identifier = identifier
    self.navigate = navigate
    store = session.messages
    desktop = session.desktop
    _dictation = StateObject(wrappedValue: session.dependencies.makeDictationViewModel())
  }

  var body: some View {
    Group {
      if screen == "home" {
        NavigationStack {
          NessaHomeView(store: store, desktop: desktop, dictation: dictation, externalToolbar: true,
            onMenu: {}, onPair: pair, onCompose: compose, onStart: start)
        }
      } else {
        NavigationStack {
          destination.toolbar {
            ToolbarItem(placement: .topBarLeading) {
              Button("Back", systemImage: "chevron.backward") { navigate("back") }
            }
          }
        }
      }
    }
    .preferredColorScheme(.dark)
    .tint(MessagesStyle.foreground)
    .sheet(isPresented: $pairing) {
      PairWithDesktopView(store: desktop).presentationBackground(MessagesStyle.background)
    }
    .alert("Nessa connection", isPresented: Binding(get: { store.error != nil },
      set: { if !$0 { store.error = nil } })) {
        Button("OK") { store.error = nil }
    } message: { Text(store.error ?? "") }
  }

  @ViewBuilder private var destination: some View {
    switch screen {
    case "agents":
      AgentsView(store: store, onOpen: openChat)
    case "channel":
      if let channel = store.channels.first(where: { $0.id == identifier }) {
        ChannelChatsView(store: store, channel: channel, dictation: dictation, onOpen: openChat, onStart: start)
      }
    case "chat":
      NessaThreadView(store: store, conversationID: identifier, dictation: dictation,
        autoFocusComposer: session.focusChat == identifier, firstMessage: session.firstMessages[identifier],
        onFirstMessageTaken: { session.firstMessages[identifier] = nil })
        .onAppear { session.focusChat = nil }
    case "connection":
      NessaConnectionView(store: store, address: $address, instance: instance, desktop: desktop,
        onPair: pair, onShowChats: { navigate("/shared") })
    case "transcript":
      LinkedDesktopThreadView(store: desktop, conversationID: identifier)
    default:
      EmptyView()
    }
  }

  private func pair() { desktop.reset(); pairing = true }

  private func path(_ route: String, _ key: String) -> String {
    "/\(route)/" + (key.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")
  }

  private func show(_ route: String) { navigate(route) }
  private func openChat(_ id: String) { show(path("chat", id)) }

  private func compose() {
    Task {
      if let id = await store.create() {
        session.focusChat = id
        openChat(id)
      }
    }
  }

  private func start(_ id: String, _ first: HomeFirstMessage) {
    session.firstMessages[id] = first
    openChat(id)
  }
}
#endif
