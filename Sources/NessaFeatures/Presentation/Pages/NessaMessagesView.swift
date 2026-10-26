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
  @State private var settings = false
  @State private var pairing = false
  @State private var linkedChats = false
  /// The sidebar under the home screen is uncovered.
  @State private var sidebar = false
  /// Messages typed on the home screen, waiting for the chat each started to send them.
  @State private var firstMessages: [String: HomeFirstMessage] = [:]
  @StateObject private var homeDictation: DictationViewModel
  private enum Route: Hashable {
    case chat(id: String, focusComposer: Bool)
    /// Every chat, with selecting, archiving and search: the inbox.
    case allChats
    /// One channel's chats.
    case channel(NessaChannel)
    /// Every agent at a glance.
    case agents
    var conversationID: String? {
      if case .chat(let id, _) = self { return id }
      return nil
    }
  }
  @State private var path: [Route] = []
  @Environment(\.scenePhase) private var scenePhase
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
    NessaSideDrawer(isOpen: $sidebar, edgeDragEnabled: path.isEmpty && !linkedChats) {
      NessaSidebar(
        store: store,
        onAgents: { show([.agents]) },
        onChannel: { show([.channel($0)]) },
        onNewChat: compose,
        onSettings: {
          closeSidebar()
          settings = true
        })
    } content: {
      stack
    }
    .preferredColorScheme(.dark)
    .tint(MessagesStyle.foreground)
    // Above the stack, not on a screen in it: a screen's tasks run again each time it comes
    // back into view, and connecting again would drop the live connection mid-transition.
    .task {
      if dependencies.mode == .development {
        await store.connect(
          address: "mock://development", credential: "", instance: "development",
          automatically: true)
        return
      }
      if instance.isEmpty { instance = UUID().uuidString.lowercased() }
      if let connection = dependencies.launchConnection {
        await store.connect(
          address: connection.address, credential: connection.credential, instance: instance,
          automatically: true)
        if store.connected { address = connection.address }
        return
      }
      // A paired Mac is the way in; the change below connects to it.
      await linkStore.load()
      if linkStore.linked != nil, dependencies.linkedProducts != nil { return }
      await store.connect(
        address: address, credential: "", instance: instance,
        restoringSavedProfile: true, automatically: true)
    }
    // The paired Mac, once read at launch or newly paired, carries the whole
    // session over its native link.
    .onChange(of: linkStore.linked?.id) { _, id in
      guard let id, id != store.linkedDesktopID, let desktop = linkStore.linked,
        let products = dependencies.linkedProducts
      else { return }
      Task {
        await store.forgetLinked()
        await store.connectLinked(desktop, instance: instance, products: products)
      }
    }
    .task(id: store.connectionRevision) {
      if store.connected { await store.watchInbox() }
    }
    .task(id: store.connectionRevision) {
      if store.connected { await store.watchReviews() }
    }
    .task(id: scenePhase) {
      guard !Task.isCancelled else { return }
      if scenePhase == .background {
        await store.suspendConnection()
      } else if scenePhase == .active {
        store.resumeConnection()
      }
    }
    .onChange(of: store.deliveryScopeRevision) { _, _ in
      path = []
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
            store: store, onOpen: { id in path.append(.chat(id: id, focusComposer: false)) },
            onAllChats: { path.append(.allChats) })
        case .channel(let channel):
          ChannelChatsView(store: store, channel: channel) { id in
            path.append(.chat(id: id, focusComposer: false))
          }
        case .allChats:
          MessagesInboxView(
            store: store, desktop: linkStore,
            onPair: pair,
            onSettings: { settings = true },
            onOpen: { identifier in
              let id = store.existingConversationID(for: identifier) ?? identifier
              if path.last?.conversationID != id {
                path.append(.chat(id: id, focusComposer: false))
              }
            },
            onCompose: compose,
            onOpenComposer: { id in
              if path.last?.conversationID != id {
                path.append(.chat(id: id, focusComposer: true))
              }
            }
          )
        }
      }
      .navigationDestination(isPresented: $linkedChats) {
        LinkedDesktopChatsView(store: linkStore)
          .navigationDestination(for: LinkedChatRoute.self) { route in
            LinkedDesktopThreadView(store: linkStore, conversationID: route.conversationID)
          }
      }
      .sheet(isPresented: $settings) {
        NessaConnectionView(
          store: store, address: $address, instance: instance, desktop: linkStore,
          onPair: {
            settings = false
            pair()
          },
          onShowChats: {
            settings = false
            linkedChats = true
          })
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
    linkedChats = false
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
