import NessaDesignSystem
import SwiftUI

/// Owns navigation and connection presentation; screen layouts live under Messages/.
public struct NessaMessagesView: View {
  @StateObject private var store: MessagesViewModel
  @StateObject private var linkStore: DesktopLinkViewModel
  private let dependencies: NessaDependencies
  @AppStorage("nessaGatewayAddress") private var address = "ws://127.0.0.1:7420/session"
  @AppStorage("nessaSurfaceInstance") private var instance = ""
  @State private var settings = false
  @State private var pairing = false
  @State private var linkedChats = false
  /// A shared chat opened from the inbox.
  @State private var sharedChat: LinkedChatRoute?
  private struct Route: Hashable {
    let conversationID: String
    let focusComposer: Bool
  }
  @State private var path: [Route] = []
  @Environment(\.scenePhase) private var scenePhase
  public init(dependencies: NessaDependencies) {
    self.dependencies = dependencies
    _store = StateObject(wrappedValue: dependencies.makeMessagesViewModel())
    _linkStore = StateObject(wrappedValue: dependencies.makeDesktopLinkViewModel())
  }
  public var body: some View {
    NavigationStack(path: $path) {
      MessagesInboxView(
        store: store, desktop: linkStore,
        onOpenShared: { sharedChat = LinkedChatRoute(conversationID: $0) },
        onPair: {
          linkStore.reset()
          pairing = true
        },
        onSettings: { settings = true },
        onOpen: { identifier in
          let id = store.existingConversationID(for: identifier) ?? identifier
          if path.last?.conversationID != id {
            path.append(Route(conversationID: id, focusComposer: false))
          }
        },
        onCompose: {
          Task {
            if let id = await store.create() {
              path.append(Route(conversationID: id, focusComposer: false))
            }
          }
        },
        onOpenComposer: { id in
          if path.last?.conversationID != id {
            path.append(Route(conversationID: id, focusComposer: true))
          }
        }
      )
      .navigationDestination(for: Route.self) { route in
        NessaThreadView(
          store: store, conversationID: route.conversationID,
          dictation: dependencies.makeDictationViewModel(), autoFocusComposer: route.focusComposer)
      }
      .navigationDestination(item: $sharedChat) { route in
        LinkedDesktopThreadView(store: linkStore, conversationID: route.conversationID)
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
            linkStore.reset()
            pairing = true
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
    // On the stack, not the inbox: the inbox's own tasks run again each time a thread is
    // popped, and connecting again would drop the live connection mid-transition.
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
      await store.connect(
        address: address, credential: "", instance: instance,
        restoringSavedProfile: true, automatically: true)
    }
    .task { await linkStore.load() }
    .task(id: store.connectionRevision) {
      if store.connected { await store.watchInbox() }
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
    .preferredColorScheme(.dark)
    .tint(MessagesStyle.foreground)
  }
}
