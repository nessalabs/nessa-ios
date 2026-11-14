#if os(iOS)
import Combine
import UIKit

/// The Exact mount follows its window, including when embedded by a list or navigation host
/// that doesn't forward controller appearance callbacks.
@MainActor final class ExactMountView: UIView {
  var mounted: ((Bool) -> Void)?
  override func didMoveToWindow() {
    super.didMoveToWindow()
    mounted?(window != nil)
  }
}

@MainActor final class ExactSessionController: UIViewController {
  private let phone: ExactPhoneSession
  private let navigate: (String) -> Void
  private var observations = Set<AnyCancellable>()
  private var tasks = [Task<Void, Never>]()
  private var feeds = [Task<Void, Never>]()
  private var connecting: Task<Void, Never>?
  private var sceneTask: Task<Void, Never>?
  private weak var alert: UIAlertController?
  private var live = false

  init(phone: ExactPhoneSession, navigate: @escaping (String) -> Void) {
    self.phone = phone
    self.navigate = navigate
    super.init(nibName: nil, bundle: nil)
  }
  required init?(coder: NSCoder) { nil }
  override func loadView() {
    let mount = ExactMountView()
    mount.mounted = { [weak self] visible in self?.mount(visible) }
    view = mount
  }

  private func mount(_ mounted: Bool) {
    guard live != mounted else { return }
    live = mounted
    observations.removeAll()
    (tasks + feeds).forEach { $0.cancel() }
    tasks.removeAll()
    feeds.removeAll()
    connecting?.cancel()
    sceneTask?.cancel()
    guard mounted, let scene = view.window?.windowScene else {
      alert?.dismiss(animated: false)
      return
    }
    let store = phone.messages, desktop = phone.desktop, dependencies = phone.dependencies
    let defaults = UserDefaults.standard
    let instanceKey = "nessaSurfaceInstance"
    let instance = (defaults.string(forKey: instanceKey)).flatMap { $0.isEmpty ? nil : $0 }
      ?? UUID().uuidString.lowercased()
    defaults.set(instance, forKey: instanceKey)
    desktop.$linked.map { $0?.id }.removeDuplicates().receive(on: RunLoop.main)
      .sink { [weak self] id in
        guard let self else { return }
        connecting?.cancel()
        guard let id, id != store.linkedDesktopID, let peer = desktop.linked, peer.id == id,
          let products = dependencies.linkedProducts else { return }
        connecting = Task {
          await store.forgetLinked()
          guard !Task.isCancelled, desktop.linked?.id == id else { return }
          await store.connectLinked(peer, instance: instance, products: products)
        }
      }.store(in: &observations)
    store.$connectionRevision.removeDuplicates().receive(on: RunLoop.main).sink { [weak self] _ in
      guard let self else { return }
      feeds.forEach { $0.cancel() }
      feeds = store.connected ? [Task { await store.watchInbox() }, Task { await store.watchReviews() }] : []
    }.store(in: &observations)
    store.$deliveryScopeRevision.removeDuplicates().dropFirst().sink { [weak self] _ in
      guard let self else { return }
      phone.firstMessages.removeAll()
      phone.focusChat = nil
      navigate("/")
    }.store(in: &observations)
    // Error strings can contain the private endpoint. Keep the system alert out of JS.
    store.$error.removeDuplicates().receive(on: RunLoop.main).sink { [weak self] error in
      self?.show(error: error)
    }.store(in: &observations)
    let notifications = NotificationCenter.default
    notifications.publisher(for: UIScene.didEnterBackgroundNotification, object: scene)
      .sink { [weak self] _ in
        self?.sceneTask?.cancel()
        self?.sceneTask = Task { await store.suspendConnection() }
      }.store(in: &observations)
    notifications.publisher(for: UIScene.didActivateNotification, object: scene)
      .sink { [weak self] _ in
        self?.sceneTask?.cancel()
        store.resumeConnection()
      }.store(in: &observations)
    if scene.activationState == .foregroundActive { store.resumeConnection() }
    tasks = [Task { await NessaDependencies.verifyNativePackageIfRequested() }, Task {
      if dependencies.mode == .development {
        await store.connect(address: "mock://development", credential: "", instance: "development", automatically: true)
      } else if let connection = dependencies.launchConnection {
        await store.connect(address: connection.address, credential: connection.credential, instance: instance, automatically: true)
        if store.connected { defaults.set(connection.address, forKey: "nessaGatewayAddress") }
      } else {
        await desktop.load()
        guard !Task.isCancelled, desktop.linked == nil || dependencies.linkedProducts == nil else { return }
        let address = defaults.string(forKey: "nessaGatewayAddress") ?? "ws://127.0.0.1:7420/session"
        await store.connect(address: address, credential: "", instance: instance, restoringSavedProfile: true, automatically: true)
      }
    }]
  }

  private func show(error: String?) {
    guard let error else { alert?.dismiss(animated: true); return }
    if let alert { alert.message = error; return }
    var presenter = view.window?.rootViewController
    while let next = presenter?.presentedViewController { presenter = next }
    guard let presenter else { return }
    let dialog = UIAlertController(title: "Nessa connection", message: error, preferredStyle: .alert)
    dialog.addAction(UIAlertAction(title: "OK", style: .default) { [weak self] _ in self?.phone.messages.error = nil })
    alert = dialog
    presenter.present(dialog, animated: true)
  }
}
#endif
