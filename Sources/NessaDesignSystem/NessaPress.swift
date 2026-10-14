import SwiftUI

/// Sinks and dims a control while a finger is on it, then springs back.
public struct NessaPressStyle: ButtonStyle {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.isEnabled) private var isEnabled
  private let scale: CGFloat
  public init(scale: CGFloat = NessaMotion.pressScale) { self.scale = scale }
  public func makeBody(configuration: Configuration) -> some View {
    let pressed = configuration.isPressed && isEnabled
    configuration.label
      .scaleEffect(pressed && !reduceMotion ? scale : 1)
      .opacity(pressed ? NessaMotion.pressOpacity : 1)
      .animation(reduceMotion ? nil : NessaMotion.press, value: pressed)
  }
}

extension ButtonStyle where Self == NessaPressStyle {
  /// The Nessa press response for glass controls and buttons.
  public static var nessaPress: NessaPressStyle { NessaPressStyle() }
}

/// Enters with nessa_ui's `nessa-enter`: a fade from slightly smaller, on a spring.
public struct NessaEntrance: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var shown = false
  let delay: Double
  public func body(content: Content) -> some View {
    content
      .opacity(shown ? 1 : 0)
      .scaleEffect(shown || reduceMotion ? 1 : NessaMotion.enterScale)
      .onAppear {
        guard !shown else { return }
        withAnimation(reduceMotion ? nil : NessaMotion.enter.delay(delay)) { shown = true }
      }
  }
}

extension View {
  /// Plays the entrance once, the first time the view appears.
  public func nessaEntrance(delay: Double = 0) -> some View {
    modifier(NessaEntrance(delay: delay))
  }
}
