import NessaDesignSystem
import SwiftUI

/// Owns navigation and connection presentation: the home screen with the sidebar under it,
/// and the chats it opens. Screen layouts live in their own views.
public struct NessaMessagesView: View {
  @StateObject private var store: MessagesViewModel
  @StateObject private var linkStore: DesktopLinkViewModel
  private let dependencies: NessaDependencies
  @AppStorage("nessaGatewayAddress") private var address = "ws://127.0.0.1:7420/session"
  @AppStorage("nessaSurfaceInstance") private var instance = ""
  @State private var pairing = false
  /// The sidebar under the home screen is uncovered.
  @State private var sidebar = false
  /// Messages typed on the home screen, waiting for the chat each started to send them.
  @State private var firstMessages: [String: HomeFirstMessage] = [:]
  @StateObject private var homeDictation: DictationViewModel
  private enum Route: Hashable {
    case chat(id: String, focusComposer: Bool)
    /// One channel's chats.
    case channel(NessaChannel)
    /// Every agent at a glance.
    case agents
    /// The person's settings, and the connection page under them.
    case settings
    case connection
    /// The chats archived from Agents.
    case archived
    /// The chats the paired Mac shares, and one of them, read-only.
    case linkedChats
    case linkedChat(String)
    var conversationID: String? {
      if case .chat(let id, _) = self { return id }
      return nil
    }
  }
  @State private var path: [Route] = []
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  public init(dependencies: NessaDependencies) {
    self.dependencies = dependencies
    _store = StateObject(wrappedValue: dependencies.makeMessagesViewModel())
    _linkStore = StateObject(wrappedValue: dependencies.makeDesktopLinkViewModel())
    _homeDictation = StateObject(wrappedValue: dependencies.makeDictationViewModel())
  }
  public var body: some View {
    // The edge drag opens the sidebar only on the home screen; anywhere deeper it is the
    // system's swipe back.
    NessaSideDrawer(isOpen: $sidebar, edgeDragEnabled: path.isEmpty) {
      NessaSidebar(
        store: store,
        onAgents: { show([.agents]) },
        onChannel: { show([.channel($0)]) },
        onNewChat: compose,
        onSettings: { show([.settings]) })
    } content: {
      stack
    }
    .preferredColorScheme(.dark)
    .tint(MessagesStyle.foreground)
    .modifier(PhoneSessionTasks(dependencies: dependencies, store: store, linkStore: linkStore))
    .onChange(of: store.deliveryScopeRevision) { _, _ in
      firstMessages.removeAll()
      path = []
    }
    // A light tap on every step back, by the back button or the edge swipe: the stack lost
    // its top and kept the rest. The sidebar replacing the stack is not a step back.
    .sensoryFeedback(.impact(weight: .light), trigger: path) { old, new in
      new.count < old.count && Array(old.prefix(new.count)) == new
    }
  }

  private var stack: some View {
    NavigationStack(path: $path) {
      NessaHomeView(
        store: store, desktop: linkStore, dictation: homeDictation,
        onMenu: openSidebar,
        onPair: pair,
        onCompose: compose,
        onStart: { id, first in
          firstMessages[id] = first
          path.append(.chat(id: id, focusComposer: false))
        }
      )
      .navigationDestination(for: Route.self) { route in
        switch route {
        case .chat(let id, let focusComposer):
          NessaThreadView(
            store: store, conversationID: id,
            dictation: dependencies.makeDictationViewModel(), autoFocusComposer: focusComposer,
            firstMessage: firstMessages[id],
            onFirstMessageTaken: { firstMessages[id] = nil })
        case .agents:
          AgentsView(
            store: store, onOpen: { id in path.append(.chat(id: id, focusComposer: false)) })
        case .channel(let channel):
          ChannelChatsView(
            store: store, channel: channel, dictation: dependencies.makeDictationViewModel(),
            onOpen: { id in path.append(.chat(id: id, focusComposer: false)) },
            onStart: { id, first in
              firstMessages[id] = first
              path.append(.chat(id: id, focusComposer: false))
            })
        case .settings:
          NessaSettingsView(
            store: store, desktop: linkStore, onConnection: { path.append(.connection) },
            onArchived: { path.append(.archived) })
        case .archived:
          ArchivedChatsView(store: store) { id in
            path.append(.chat(id: id, focusComposer: false))
          }
        case .connection:
          NessaConnectionView(
            store: store, address: $address, instance: instance, desktop: linkStore,
            onPair: pair, onShowChats: { path.append(.linkedChats) })
        case .linkedChats:
          LinkedDesktopChatsView(store: linkStore) { path.append(.linkedChat($0)) }
        case .linkedChat(let id):
          LinkedDesktopThreadView(store: linkStore, conversationID: id)
        }
      }
      .sheet(isPresented: $pairing) {
        PairWithDesktopView(store: linkStore)
          .presentationBackground(MessagesStyle.background)
      }
      .alert(
        "Nessa connection",
        isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })
      ) {
        Button("OK") { store.error = nil }
      } message: {
        Text(store.error ?? "")
      }
    }
  }

  private func pair() {
    linkStore.reset()
    pairing = true
  }

  private func openSidebar() {
    withAnimation(reduceMotion ? nil : NessaDrawerStyle.motion) { sidebar = true }
  }

  private func closeSidebar() {
    withAnimation(reduceMotion ? nil : NessaDrawerStyle.motion) { sidebar = false }
  }

  /// Opens what the sidebar picked in place of whatever was open, as the sidebar closes.
  private func show(_ routes: [Route]) {
    path = routes
    closeSidebar()
  }

  /// A new, empty chat, opened with its composer ready.
  private func compose() {
    Task {
      if let id = await store.create() {
        show([.chat(id: id, focusComposer: true)])
      }
    }
  }
}
