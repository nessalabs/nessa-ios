import SwiftUI

#if os(iOS)
  import UIKit
#endif

/// Native page transitions keep selection in sync only after a swipe completes.
struct LoopingPhotoPager<Card: View>: View {
  let count: Int
  @Binding var selection: Int
  @ViewBuilder let card: (Int) -> Card
  var body: some View {
    #if os(iOS)
      NativePhotoPager(count: count, selection: $selection, card: card)
        .accessibilityAction(named: Text("Next photo")) { advance(1) }
        .accessibilityAction(named: Text("Previous photo")) { advance(-1) }
    #else
      TabView(selection: $selection) {
        ForEach(0..<count, id: \.self) { index in card(index).tag(index) }
      }
    #endif
  }
  private func advance(_ direction: Int) {
    guard count > 1 else { return }
    selection = (selection + direction + count) % count
  }
}

#if os(iOS)
  private struct NativePhotoPager<Card: View>: UIViewControllerRepresentable {
    let count: Int
    @Binding var selection: Int
    let card: (Int) -> Card
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIPageViewController {
      let controller = UIPageViewController(
        transitionStyle: .scroll, navigationOrientation: .horizontal)
      controller.view.backgroundColor = .clear
      controller.dataSource = context.coordinator
      controller.delegate = context.coordinator
      if count > 0 {
        let index = min(max(selection, 0), count - 1)
        context.coordinator.visibleIndex = index
        controller.setViewControllers(
          [context.coordinator.page(index)], direction: .forward, animated: false)
      }
      return controller
    }
    func updateUIViewController(_ controller: UIPageViewController, context: Context) {
      let coordinator = context.coordinator
      let countChanged = coordinator.parent.count != count
      if countChanged { coordinator.pages = [:] }
      coordinator.parent = self
      for (index, page) in coordinator.pages where index < count { page.rootView = card(index) }
      guard count > 0 else {
        controller.setViewControllers(nil, direction: .forward, animated: false)
        return
      }
      let index = min(max(selection, 0), count - 1)
      guard !coordinator.transitioning else {
        if countChanged || index != coordinator.visibleIndex || coordinator.pendingIndex != nil {
          coordinator.pendingIndex = index
        }
        return
      }
      if countChanged || coordinator.visibleIndex != index {
        coordinator.visibleIndex = index
        controller.setViewControllers(
          [coordinator.page(index)], direction: .forward, animated: false)
      }
    }
    final class Page: UIHostingController<Card> {
      let index: Int
      init(index: Int, content: Card) {
        self.index = index
        super.init(rootView: content)
        view.backgroundColor = .clear
      }
      @MainActor required dynamic init?(coder: NSCoder) { fatalError("Use init(index:content:)") }
    }
    final class Coordinator: NSObject, UIPageViewControllerDataSource, UIPageViewControllerDelegate
    {
      var parent: NativePhotoPager
      var pages: [Int: Page] = [:]
      var visibleIndex = 0
      var transitioning = false
      var pendingIndex: Int?
      init(_ parent: NativePhotoPager) { self.parent = parent }
      func page(_ index: Int) -> Page {
        if let page = pages[index] { return page }
        let page = Page(index: index, content: parent.card(index))
        pages[index] = page
        return page
      }
      func pageViewController(
        _ controller: UIPageViewController, viewControllerBefore viewController: UIViewController
      ) -> UIViewController? {
        guard parent.count > 1, let current = viewController as? Page else { return nil }
        return page((current.index + parent.count - 1) % parent.count)
      }
      func pageViewController(
        _ controller: UIPageViewController, viewControllerAfter viewController: UIViewController
      ) -> UIViewController? {
        guard parent.count > 1, let current = viewController as? Page else { return nil }
        return page((current.index + 1) % parent.count)
      }
      func pageViewController(
        _ controller: UIPageViewController,
        willTransitionTo pendingViewControllers: [UIViewController]
      ) {
        transitioning = true
      }
      func pageViewController(
        _ controller: UIPageViewController, didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController], transitionCompleted completed: Bool
      ) {
        transitioning = false
        if let pendingIndex, parent.count > 0 {
          self.pendingIndex = nil
          let index = min(pendingIndex, parent.count - 1)
          visibleIndex = index
          controller.setViewControllers([page(index)], direction: .forward, animated: false)
          parent.selection = index
          return
        }
        guard completed, let current = controller.viewControllers?.first as? Page else { return }
        visibleIndex = current.index
        parent.selection = current.index
      }
    }
  }
#endif
