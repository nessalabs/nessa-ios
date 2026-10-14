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
      .opacity(isEnabled ? (pressed ? NessaMotion.pressOpacity : 1) : NessaMotion.disabledOpacity)
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

/// The one filled call to action on a screen: the lit accent capsule, with the Nessa press.
public struct NessaPrimaryButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  public init() {}
  public func makeBody(configuration: Configuration) -> some View {
    let pressed = configuration.isPressed && isEnabled
    configuration.label
      .font(MessagesStyle.title)
      .foregroundStyle(isEnabled ? NessaColor.foreground : NessaColor.mutedForeground)
      .padding(.horizontal, NessaSpacing.lg)
      .frame(minHeight: MessagesStyle.controlHeight)
      .background(
        isEnabled ? AnyShapeStyle(MessagesStyle.outgoingFill) : AnyShapeStyle(NessaColor.muted),
        in: Capsule())
      .scaleEffect(pressed && !reduceMotion ? NessaMotion.pressScale : 1)
      .opacity(pressed ? NessaMotion.pressOpacity : 1)
      .animation(reduceMotion ? nil : NessaMotion.press, value: pressed)
  }
}

extension ButtonStyle where Self == NessaPrimaryButtonStyle {
  public static var nessaPrimary: NessaPrimaryButtonStyle { NessaPrimaryButtonStyle() }
}

/// The glass search capsule.
public struct NessaSearchField: View {
  @Binding private var text: String
  private let prompt: String
  public init(_ prompt: String = "Search", text: Binding<String>) {
    self.prompt = prompt
    self._text = text
  }
  public var body: some View {
    HStack(spacing: NessaSpacing.xs) {
      Image(systemName: "magnifyingglass").font(MessagesStyle.icon)
        .foregroundStyle(MessagesStyle.secondary)
      TextField(prompt, text: $text).font(MessagesStyle.body)
      if !text.isEmpty {
        Button {
          text = ""
        } label: {
          Image(systemName: "xmark.circle.fill").foregroundStyle(MessagesStyle.secondary)
        }
        .buttonStyle(.nessaPress)
        .accessibilityLabel("Clear search")
        .transition(.scale.combined(with: .opacity))
      }
    }
    .padding(.horizontal, NessaSpacing.md)
    .frame(height: MessagesStyle.composerHeight)
    .messagesGlass()
    .animation(NessaMotion.morph, value: text.isEmpty)
  }
}
