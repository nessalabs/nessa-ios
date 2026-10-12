import NessaDesignSystem
import SwiftUI

/// Owns navigation and connection presentation; screen layouts live under Messages/.
public struct NessaMessagesView: View {
  @StateObject private var store: MessagesViewModel
  private let dependencies: NessaDependencies
  @AppStorage("nessaGatewayAddress") private var address = "ws://127.0.0.1:7420/session"
  @AppStorage("nessaSurfaceInstance") private var instance = ""
  @State private var settings = false
  @State private var path: [String] = []
  @Environment(\.scenePhase) private var scenePhase
  public init(dependencies: NessaDependencies) {
    self.dependencies = dependencies
    _store = StateObject(wrappedValue: dependencies.makeMessagesViewModel())
  }
  public var body: some View {
    NavigationStack(path: $path) {
      MessagesInboxView(
        store: store, onSettings: { settings = true },
        onOpen: { path.append($0) },
        onCompose: { Task { if let id = await store.create() { path.append(id) } } }
      )
      .navigationDestination(for: String.self) { id in
        NessaThreadView(
          store: store, conversationID: id,
          dictation: dependencies.makeDictationViewModel())
      }
      .sheet(isPresented: $settings) {
        if dependencies.mode == .development {
          DevelopmentInfoPage()
        } else {
          NessaConnectionView(store: store, address: $address, instance: instance)
        }
      }
      .alert(
        "Nessa connection",
        isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })
      ) {
        Button("OK") { store.error = nil }
      } message: {
        Text(store.error ?? "")
      }
      .task {
        if dependencies.mode == .development {
          await store.connect(
            address: "mock://development", credential: "", instance: "development")
          return
        }
        if instance.isEmpty { instance = UUID().uuidString.lowercased() }
        if let connection = dependencies.launchConnection {
          await store.connect(
            address: connection.address, credential: connection.credential, instance: instance)
          if store.connected { address = connection.address }
          return
        }
        let credential = store.savedCredential()
        if !credential.isEmpty {
          await store.connect(address: address, credential: credential, instance: instance)
        }
      }
    }
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
    .preferredColorScheme(.dark)
    .tint(MessagesStyle.foreground)
  }
}
