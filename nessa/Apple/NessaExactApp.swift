import ExactGroupedLists
import ExactKit
import ExactMarkdown
import ExactSurfaces
import UIKit

@main
final class NessaExactApp: UIResponder, UIApplicationDelegate {
  func application(_ application: UIApplication,
    didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
    ExactGroupedLists.install()
    ExactMarkdown.install()
    ExactSurfaces.install()
    return true
  }

  func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
    options: UIScene.ConnectionOptions) -> UISceneConfiguration {
    let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
    configuration.delegateClass = PhoneScene.self
    return configuration
  }
}

final class PhoneScene: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?
  private var content: ExactView?

  func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
    guard let scene = scene as? UIWindowScene else { return }
    let window = UIWindow(windowScene: scene)
    window.overrideUserInterfaceStyle = .dark
    let content = ExactView(session: ExactApp.shared.makeSession(label: "Nessa"))
    let controller = UIViewController()
    controller.view = content
    window.rootViewController = controller
    self.content = content
    self.window = window
    window.makeKeyAndVisible()
  }

  func sceneDidDisconnect(_ scene: UIScene) {
    content?.session.destroy()
    content = nil
    window = nil
  }
}
