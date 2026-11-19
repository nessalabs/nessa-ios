import Combine
import NessaDesignSystem
import SwiftUI
#if os(iOS)
import UIKit

extension ExactPhoneSession {
  public func connectionBridge(changed: @escaping () -> Void) -> ExactConnection {
    ExactConnection(messages: messages, desktop: desktop, changed: changed)
  }
}

#endif

/// Contract receives presentation state. The endpoint, credential, pairing code and camera
/// frames remain in their native controls and pass directly to the existing phone services.
@MainActor public final class ExactConnection: ObservableObject {
  fileprivate let messages: MessagesViewModel
  fileprivate let desktop: DesktopLinkViewModel
  @Published var address = ""
  @Published var credential = ""
  @Published var code = ""
  private var subscriptions = Set<AnyCancellable>()
  private var pairingVisit: UUID?

  init(messages: MessagesViewModel, desktop: DesktopLinkViewModel, changed: @escaping () -> Void) {
    self.messages = messages
    self.desktop = desktop
    messages.objectWillChange.merge(with: desktop.objectWillChange).merge(with: objectWillChange)
      .receive(on: RunLoop.main)
      .compactMap { [weak self] _ in self?.state as NSDictionary? }
      .removeDuplicates()
      .sink { _ in changed() }.store(in: &subscriptions)
  }

  public var state: [String: Any] {
    var peer = ""
    var peers: [[String: String]] = []
    var failure = ""
    switch desktop.phase {
    case .choosing(let found): peers = found.map { ["id": $0.id, "name": $0.name] }
    case .enrolling(let found), .approving(let found): peer = found.name
    case .linked(let linked): peer = linked.name
    case .failed(let reason): failure = DesktopLinkViewModel.sentence(reason)
    default: break
    }
    return [
      "connected": messages.connected, "saved": messages.hasSavedConnection,
      "busy": messages.busy, "setupBusy": messages.phoneSetupBusy,
      "hasCredential": !credential.isEmpty, "hasError": messages.error != nil || messages.phoneSyncError != nil,
      "available": desktop.available, "linked": desktop.linked != nil,
      "desktop": desktop.linked?.name ?? "", "desktopID": desktop.linked?.id.uuidString ?? "",
      "phase": desktop.phase.screenKey, "peer": peer, "peers": peers, "failure": failure,
      "validCode": OrbCode.parse(code) != nil,
    ]
  }

  public func perform(_ action: String, key: String) async {
    switch action {
    case "connect":
      guard !messages.connected, !messages.hasSavedConnection, !messages.busy, !credential.isEmpty else { return }
      let selected = address
      let instance = UserDefaults.standard.string(forKey: "nessaSurfaceInstance") ?? ""
      await messages.connect(address: selected, credential: credential, instance: instance)
      if messages.connected { UserDefaults.standard.set(selected, forKey: "nessaGatewayAddress") }
    case "reconnect":
      guard !messages.connected, messages.hasSavedConnection, !messages.busy, !messages.phoneSetupBusy else { return }
      await messages.reconnectSavedConnection()
    case "disconnect":
      guard messages.connected else { return }
      await messages.manualDisconnect()
    case "forget":
      guard let id = desktop.linked?.id, id.uuidString == key else { return }
      await messages.forgetLinked()
      if desktop.linked?.id == id { await desktop.unlink() }
    case "reset":
      guard pairingVisit != nil else { return }
      desktop.reset()
    case "pair":
      guard pairingVisit != nil, desktop.available, OrbCode.parse(code) != nil,
        desktop.phase.screenKey == "idle" || desktop.phase.screenKey == "failed" else { return }
      desktop.submit(code: code)
    case "choose":
      guard pairingVisit != nil, case .choosing(let peers) = desktop.phase,
        let chosen = peers.first(where: { $0.id == key }) else { return }
      desktop.choose(chosen)
    default: break
    }
  }

  fileprivate var savedAddress: String {
    UserDefaults.standard.string(forKey: "nessaGatewayAddress") ?? "ws://127.0.0.1:7420/session"
  }

  fileprivate func enterPairing(_ id: UUID) {
    guard pairingVisit != id else { return }
    pairingVisit = id
    code = ""
    desktop.reset()
  }

  fileprivate func leavePairing(_ id: UUID) {
    guard pairingVisit == id else { return }
    pairingVisit = nil
    code = ""
    if desktop.busy || desktop.phase.screenKey == "choosing" { desktop.reset() }
  }

  #if os(iOS)
  public func control(_ kind: String, measured: @escaping (CGSize) -> Void) -> UIViewController {
    let growsWithText = ["credentials", "endpoint", "error", "code"].contains(kind)
    let input = ConnectionInput(owner: self, kind: kind)
      .fixedSize(horizontal: false, vertical: growsWithText)
      .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
        if growsWithText, size.width > 0, size.height > 0 { measured(size) }
      }
    let host = UIHostingController(rootView: input)
    host.safeAreaRegions = []
    host.view.backgroundColor = .clear
    return host
  }
  #endif
}

#if os(iOS)
private struct ConnectionInput: View {
  @ObservedObject var owner: ExactConnection
  @ObservedObject var messages: MessagesViewModel
  let kind: String
  @State private var visit = UUID()

  init(owner: ExactConnection, kind: String) {
    self.owner = owner
    messages = owner.messages
    self.kind = kind
  }

  var body: some View {
    Group {
      switch kind {
      case "credentials":
        VStack(alignment: .leading, spacing: 0) {
          TextField("wss://your-host/session", text: $owner.address).nessaCredentialInput()
            .accessibilityIdentifier("gateway-address")
            .frame(maxWidth: .infinity, minHeight: MessagesStyle.controlHeight, alignment: .leading)
          Divider()
          SecureField("Credential", text: $owner.credential).nessaCredentialInput()
            .accessibilityIdentifier("gateway-credential")
            .frame(maxWidth: .infinity, minHeight: MessagesStyle.controlHeight, alignment: .leading)
        }.font(MessagesStyle.body).padding(.horizontal, NessaSpacing.md).nessaCard()
          .onAppear { owner.address = messages.currentGatewayAddress ?? owner.savedAddress }
          .onDisappear { owner.credential = ""; owner.address = "" }
      case "endpoint":
        Text(messages.connected ? (messages.currentGatewayAddress ?? owner.savedAddress)
          : (messages.savedReconnectGatewayAddress ?? "Saved gateway unavailable"))
          .font(NessaType.mono).textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
      case "error":
        Text(messages.error ?? messages.phoneSyncError ?? "")
          .font(MessagesStyle.caption).foregroundStyle(MessagesStyle.secondary)
          .frame(maxWidth: .infinity, alignment: .leading)
      case "pair-lifetime":
        Color.clear.onAppear { owner.enterPairing(visit) }.onDisappear { owner.leavePairing(visit) }
      case "camera":
        OrbCameraWindow(store: owner.desktop) { code in
          owner.code = code
          Task { await owner.perform("pair", key: "") }
        }
      case "code":
        TextField("Or type the code", text: $owner.code).font(PairingStyle.codeFont)
          .multilineTextAlignment(.center).nessaCodeInput().nessaCard()
          .accessibilityIdentifier("pair-code")
          .onSubmit { Task { await owner.perform("pair", key: "") } }
      default: EmptyView()
      }
    }.preferredColorScheme(.dark).foregroundStyle(MessagesStyle.foreground)
  }
}
#endif
