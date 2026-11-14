import Combine
import Foundation
#if os(iOS)
import UIKit
import AVFoundation

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
  private var credentialVisit: UUID?
  @Published private(set) var cameraState = "asking"

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
      "validCode": OrbCode.parse(code) != nil, "cameraState": cameraState,
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
    PrivateConnectionControl(owner: self, kind: kind, measured: measured)
  }

  fileprivate func visit(_ kind: String, id: UUID, mounted: Bool) {
    if kind == "pair-lifetime" {
      if mounted { enterPairing(id) } else { leavePairing(id) }
    } else if kind == "credential" {
      if mounted { credentialVisit = id; credential = "" }
      else if credentialVisit == id { credentialVisit = nil; credential = ""; address = "" }
    }
  }
  fileprivate func camera(_ state: String) { if cameraState != state { cameraState = state } }
  #endif
}

#if os(iOS)
/// Only content that cannot enter the Contract tree is rendered here. Exact owns
/// card layout, validation, camera permission guidance, and pairing actions.
@MainActor private final class PrivateConnectionControl: UIViewController, UITextFieldDelegate {
  private let owner: ExactConnection
  private let kind: String
  private let measured: (CGSize) -> Void
  private let visit = UUID()
  private var observer: AnyCancellable?
  private var permission: Task<Void, Never>?
  private var reader: CameraOrbReader?
  private var preview: AVCaptureVideoPreviewLayer?
  private var field: UITextField?
  private var label: UITextView?
  private var lastSize = CGSize.zero
  private var mounted = false

  init(owner: ExactConnection, kind: String, measured: @escaping (CGSize) -> Void) {
    self.owner = owner
    self.kind = kind
    self.measured = measured
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { nil }

  override func loadView() {
    let root = ExactMountView()
    root.mounted = { [weak self] visible in self?.mount(visible) }
    view = root
    switch kind {
    case "code", "credential", "address":
      let field = UITextField()
      field.delegate = self
      field.autocorrectionType = .no
      field.autocapitalizationType = kind == "code" ? .allCharacters : .none
      field.spellCheckingType = .no
      field.isSecureTextEntry = kind == "credential"
      field.textColor = .label
      field.font = kind == "code" ? .monospacedSystemFont(ofSize: 24, weight: .semibold) : .preferredFont(forTextStyle: .body)
      field.adjustsFontForContentSizeCategory = true
      field.placeholder = ["code": "Or type the code", "credential": "Credential", "address": "wss://your-host/session"][kind]
      field.accessibilityIdentifier = kind == "code" ? "pair-code" : "gateway-" + kind
      field.textAlignment = kind == "code" ? .center : .natural
      field.addTarget(self, action: #selector(edited), for: .editingChanged)
      root.addSubview(field)
      self.field = field
    case "endpoint", "error":
      let label = UITextView()
      label.backgroundColor = .clear
      label.isEditable = false
      label.isSelectable = kind == "endpoint"
      label.isScrollEnabled = false
      label.textContainerInset = .zero
      label.textContainer.lineFragmentPadding = 0
      label.font = kind == "endpoint" ? .monospacedSystemFont(ofSize: 14, weight: .regular) : .preferredFont(forTextStyle: .caption1)
      label.textColor = kind == "endpoint" ? .label : .secondaryLabel
      label.adjustsFontForContentSizeCategory = true
      root.addSubview(label)
      self.label = label
    case "camera":
      let reader = CameraOrbReader()
      let preview = AVCaptureVideoPreviewLayer(session: reader.session)
      preview.videoGravity = .resizeAspectFill
      root.layer.addSublayer(preview)
      self.reader = reader
      self.preview = preview
    default: break
    }
  }

  private func mount(_ visible: Bool) {
    guard mounted != visible else { return }
    mounted = visible
    owner.visit(kind, id: visit, mounted: visible)
    observer = nil
    permission?.cancel()
    if !visible {
      reader?.stop()
      field?.text = nil
      return
    }
    if let field {
      if kind == "address" { owner.address = owner.messages.currentGatewayAddress ?? owner.savedAddress }
      field.text = kind == "address" ? owner.address : (kind == "code" ? owner.code : owner.credential)
    }
    if reader != nil {
      observer = owner.desktop.$phase.map(\.screenKey).removeDuplicates().receive(on: RunLoop.main)
        .sink { [weak self] _ in self?.updateCamera() }
    } else if label != nil {
      updateLabel()
      observer = owner.messages.objectWillChange.receive(on: RunLoop.main)
        .sink { [weak self] _ in self?.updateLabel() }
    }
  }

  private func updateCamera() {
    permission?.cancel()
    reader?.stop()
    preview?.isHidden = true
    guard owner.desktop.phase.screenKey == "idle", let reader else { return }
    owner.camera("asking")
    permission = Task { [weak self] in
      let access = await CameraOrbReader.availability()
      guard let self, !Task.isCancelled, mounted, owner.desktop.phase.screenKey == "idle" else { return }
      guard access == .ready else { owner.camera("denied"); return }
      preview?.isHidden = false
      owner.camera("ready")
      reader.start { [weak self] code in
        Task { @MainActor in
          guard let self, self.mounted, self.owner.desktop.phase.screenKey == "idle" else { return }
          UIImpactFeedbackGenerator(style: .light).impactOccurred()
          self.owner.code = code
          await self.owner.perform("pair", key: "")
        }
      }
    }
  }

  private func updateLabel() {
    let m = owner.messages
    label?.text = kind == "error" ? m.error ?? m.phoneSyncError ?? "" :
      (m.connected ? m.currentGatewayAddress ?? owner.savedAddress : m.savedReconnectGatewayAddress ?? "Saved gateway unavailable")
    view.setNeedsLayout()
  }
  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    field?.frame = view.bounds
    preview?.frame = view.bounds
    guard let label, view.bounds.width > 0 else { return }
    let size = label.sizeThatFits(CGSize(width: view.bounds.width, height: .greatestFiniteMagnitude))
    label.frame = CGRect(origin: .zero, size: CGSize(width: view.bounds.width, height: size.height))
    let fit = CGSize(width: view.bounds.width, height: ceil(size.height))
    if fit != lastSize { lastSize = fit; measured(fit) }
  }
  @objc private func edited() {
    let value = field?.text ?? ""
    switch kind { case "address": owner.address = value; case "credential": owner.credential = value; case "code": owner.code = value; default: break }
  }
  func textFieldShouldReturn(_ textField: UITextField) -> Bool {
    textField.resignFirstResponder()
    if kind == "code" { Task { await owner.perform("pair", key: "") } }
    return true
  }
}
#endif
