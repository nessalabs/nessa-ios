import NessaDesignSystem
import SwiftUI

enum PhotoCardSwipe {
  static func direction(distance: CGFloat, velocity: CGFloat, width: CGFloat) -> Int? {
    guard
      abs(distance) > width * MessagesStyle.photoSwipeThreshold
        || abs(velocity) > MessagesStyle.photoSwipeVelocity
    else { return nil }
    let projected = distance + velocity * MessagesStyle.photoSwipeProjection
    return (projected == 0 ? distance : projected) < 0 ? 1 : -1
  }
}

#if os(iOS)
  import UIKit

  /// Back navigation yields to swipes that start inside a photo surface.
  protocol PhotoSwipeRegion: AnyObject {}

  struct PhotoCardStack<Card: View>: UIViewControllerRepresentable {
    let count: Int
    @Binding var selection: Int
    @ViewBuilder let card: (Int) -> Card
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> Controller {
      let controller = Controller(rootView: content(context.coordinator.motion))
      controller.view.backgroundColor = .clear
      controller.view.clipsToBounds = false
      let pan = UIPanGestureRecognizer(
        target: context.coordinator, action: #selector(Coordinator.pan(_:)))
      pan.delegate = context.coordinator
      controller.view.addGestureRecognizer(pan)
      return controller
    }
    func updateUIViewController(_ controller: Controller, context: Context) {
      context.coordinator.parent = self
      controller.rootView = content(context.coordinator.motion)
    }
    private func content(_ motion: Motion) -> StackContent {
      StackContent(count: count, selection: $selection, motion: motion, card: card)
    }
    final class Controller: UIHostingController<StackContent>, PhotoSwipeRegion {}
    final class Motion: ObservableObject {
      @Published var offset: CGFloat = 0
      @Published var settling = false
      @Published var direction = 1
    }
    struct StackContent: View {
      let count: Int
      @Binding var selection: Int
      @ObservedObject var motion: Motion
      let card: (Int) -> Card
      var body: some View {
        ZStack {
          if count > 0 {
            let progress = min(abs(motion.offset) / MessagesStyle.photoWidth, 1)
            ForEach(Array((1..<min(count, 3)).reversed()), id: \.self) { depth in
              card((selection + motion.direction * depth + count) % count)
                .rotationEffect(
                  .degrees(Double(depth) * MessagesStyle.photoStackTilt * (1 - progress))
                )
                .offset(
                  x: CGFloat(depth) * NessaSpacing.xs * (1 - progress),
                  y: -CGFloat(depth) * NessaSpacing.xs * (1 - progress)
                )
                .allowsHitTesting(false).accessibilityHidden(true)
            }
            card(min(selection, count - 1))
              .rotationEffect(
                .degrees(
                  Double(motion.offset / MessagesStyle.photoWidth) * MessagesStyle.photoSwipeTilt)
              )
              .offset(x: motion.offset, y: abs(motion.offset) * MessagesStyle.photoSwipeLift)
              .allowsHitTesting(!motion.settling)
          }
        }.accessibilityAction(named: Text("Next photo")) { advance(1) }
          .accessibilityAction(named: Text("Previous photo")) { advance(-1) }
      }
      private func advance(_ direction: Int) {
        guard count > 1, !motion.settling else { return }
        selection = (selection + direction + count) % count
      }
    }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
      var parent: PhotoCardStack
      let motion = Motion()
      init(_ parent: PhotoCardStack) { self.parent = parent }
      func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard parent.count > 1, !motion.settling, let pan = recognizer as? UIPanGestureRecognizer
        else { return false }
        let velocity = pan.velocity(in: pan.view)
        return abs(velocity.x) > abs(velocity.y)
      }
      @objc func pan(_ pan: UIPanGestureRecognizer) {
        let distance = pan.translation(in: pan.view).x
        switch pan.state {
        case .began, .changed:
          if abs(distance) > 1 { motion.direction = distance < 0 ? 1 : -1 }
          motion.offset = distance
        case .ended:
          let velocity = pan.velocity(in: pan.view).x
          if let direction = PhotoCardSwipe.direction(
            distance: distance, velocity: velocity, width: MessagesStyle.photoWidth)
          {
            motion.direction = direction
            finish(direction: direction)
          } else {
            reset()
          }
        case .cancelled, .failed: reset()
        default: break
        }
      }
      private func finish(direction: Int) {
        motion.settling = true
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        withAnimation(
          reduceMotion ? nil : MessagesStyle.photoSwipeAnimation,
          completionCriteria: .logicallyComplete
        ) {
          motion.offset =
            CGFloat(-direction) * MessagesStyle.photoWidth * MessagesStyle.photoSwipeExit
        } completion: {
          var transaction = Transaction()
          transaction.disablesAnimations = true
          withTransaction(transaction) {
            if self.parent.count > 0 {
              self.parent.selection =
                (self.parent.selection + direction + self.parent.count) % self.parent.count
            }
            self.motion.offset = 0
            self.motion.settling = false
          }
        }
      }
      private func reset() {
        withAnimation(
          UIAccessibility.isReduceMotionEnabled ? nil : MessagesStyle.photoSwipeReturnAnimation
        ) {
          motion.offset = 0
        }
      }
    }
  }
#else
  struct PhotoCardStack<Card: View>: View {
    let count: Int
    @Binding var selection: Int
    @ViewBuilder let card: (Int) -> Card
    var body: some View { LoopingPhotoPager(count: count, selection: $selection, card: card) }
  }
#endif
