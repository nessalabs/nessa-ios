import SwiftUI

#if os(iOS)
  import UIKit

  /// Keeps UIKit's interactive pop transition available when the system bar is hidden.
  struct NativeBackSwipe: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController, UIGestureRecognizerDelegate {
      private final class Binding {
        weak var recognizer: UIGestureRecognizer?
        weak var delegate: (any UIGestureRecognizerDelegate)?
        let enabled: Bool
        init(_ recognizer: UIGestureRecognizer) {
          self.recognizer = recognizer
          delegate = recognizer.delegate
          enabled = recognizer.isEnabled
        }
      }
      private var bindings: [Binding] = []
      private var active = false
      private weak var navigation: UINavigationController?
      override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        active = true
        install()
      }
      override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if active && view.window != nil { install() }
      }
      private func install() {
        guard
          let navigation = navigationController
            ?? findNavigation(in: view.window?.rootViewController)
        else { return }
        self.navigation = navigation
        var recognizers = [navigation.interactivePopGestureRecognizer].compactMap { $0 }
        if #available(iOS 26.0, *), let content = navigation.interactiveContentPopGestureRecognizer
        {
          recognizers.append(content)
        }
        if bindings.isEmpty { bindings = recognizers.map { Binding($0) } }
        for recognizer in recognizers {
          recognizer.delegate = self
          recognizer.isEnabled = true
        }
      }
      private func findNavigation(in controller: UIViewController?) -> UINavigationController? {
        guard let controller else { return nil }
        if let navigation = controller as? UINavigationController,
          view.isDescendant(of: navigation.view)
        {
          return navigation
        }
        for child in controller.children {
          if let navigation = findNavigation(in: child) { return navigation }
        }
        return nil
      }
      override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        active = false
        for binding in bindings where binding.recognizer?.delegate === self {
          binding.recognizer?.delegate = binding.delegate
          binding.recognizer?.isEnabled = binding.enabled
        }
        bindings = []
      }
      func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let navigation else { return false }
        if gestureRecognizer !== navigation.interactivePopGestureRecognizer,
          isPhotoPager(
            navigation.view.hitTest(gestureRecognizer.location(in: navigation.view), with: nil))
        {
          return false
        }
        if let pan = gestureRecognizer as? UIPanGestureRecognizer {
          let velocity = pan.velocity(in: navigation.view)
          guard velocity.x > abs(velocity.y) else { return false }
        }
        return navigation.viewControllers.count > 1 && navigation.transitionCoordinator == nil
      }
      func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch)
        -> Bool
      {
        gestureRecognizer === navigation?.interactivePopGestureRecognizer
          || !isPhotoPager(touch.view)
      }
      private func isPhotoPager(_ touchedView: UIView?) -> Bool {
        var candidate = touchedView
        while let current = candidate {
          if current.next is UIPageViewController || current.next is any PhotoSwipeRegion {
            return true
          }
          candidate = current.superview
        }
        return false
      }
    }
  }
#endif

extension View {
  @ViewBuilder func nessaNativeBackSwipe() -> some View {
    #if os(iOS)
      self.background(NativeBackSwipe().allowsHitTesting(false))
    #else
      self
    #endif
  }
}
