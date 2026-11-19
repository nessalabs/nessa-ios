import SwiftUI

/// Connection and feed tasks live for the lifetime of the phone session, across every route.
struct PhoneSessionTasks: ViewModifier {
  let dependencies: NessaDependencies
  @ObservedObject var store: MessagesViewModel
  @ObservedObject var linkStore: DesktopLinkViewModel
  @AppStorage("nessaGatewayAddress") private var address = "ws://127.0.0.1:7420/session"
  @AppStorage("nessaSurfaceInstance") private var instance = ""
  @Environment(\.scenePhase) private var scenePhase

  func body(content: Content) -> some View {
    content
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
  }
}
