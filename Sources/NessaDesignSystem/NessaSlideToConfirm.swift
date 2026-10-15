import SwiftUI

/// A deliberate confirm: pick up the knob and slide it to the end of the track, like the old
/// slide to unlock. The knob is the tint, and behind it the track fills with the tint, faint
/// at the start and deepening toward the knob and toward the end. Let go early and the knob
/// springs back and the fill drains with it.
///
/// Given `armed`, the slide can also stand in for a bar at rest: it shows `restingLabel` and
/// the knob is a button. A tap on the knob arms it (the label turns into `label`, the knob
/// nudges toward the end), and only then does it slide. Clear `armed` to put it back.
public struct NessaSlideToConfirm: View {
  private let label: String
  private let restingLabel: String?
  private let armed: Binding<Bool>?
  private let symbol: String
  private let tint: Color
  private let height: CGFloat
  private let onConfirm: () -> Void
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// The live drag lives in gesture state, so a drag the system cancels (the sheet taking the
  /// pan, a second touch) springs back just like one let go early, instead of sticking.
  @GestureState(resetTransaction: Transaction(animation: SlideStyle.springBack))
  private var drag: CGFloat = 0
  @GestureState private var holding = false
  @State private var confirmed = false
  /// Counts arms; each one plays the hint that the knob now moves, a short push toward the
  /// end and back.
  @State private var nudges = 0

  /// `height` sizes the track, so it can stand in for a bar of the same height; the knob
  /// keeps the same inset at any height.
  public init(
    _ label: String, restingLabel: String? = nil, armed: Binding<Bool>? = nil,
    symbol: String = "trash", tint: Color = NessaColor.destructive,
    height: CGFloat? = nil, onConfirm: @escaping () -> Void
  ) {
    self.label = label
    self.restingLabel = restingLabel
    self.armed = armed
    self.symbol = symbol
    self.tint = tint
    self.height = height ?? SlideStyle.trackHeight
    self.onConfirm = onConfirm
  }

  /// Without an `armed` binding the slide is always ready.
  private var isArmed: Bool { armed?.wrappedValue ?? true }

  public var body: some View {
    GeometryReader { geometry in
      let travel = max(geometry.size.width - height, 1)
      let offset = confirmed ? travel : min(max(drag, 0), travel)
      let progress = offset / travel
      ZStack(alignment: .leading) {
        Capsule().fill(NessaColor.muted)
          .overlay(Capsule().strokeBorder(NessaColor.hairline, lineWidth: 1))
        Text(isArmed ? label : restingLabel ?? label).font(SlideStyle.label)
          .contentTransition(.numericText())
          .nessaShimmer(active: isEnabled && isArmed && !holding)
          .frame(maxWidth: .infinity)
          .padding(.leading, height)
          .opacity(1 - min(progress / SlideStyle.labelFadeEnd, 1))
        NessaSlideFill(progress: progress, travel: travel, height: height, tint: tint)
        knob
          .keyframeAnimator(initialValue: CGFloat(0), trigger: nudges) { knob, push in
            knob.offset(x: push)
          } keyframes: { _ in
            CubicKeyframe(SlideStyle.nudgeDistance, duration: SlideStyle.nudgeOut)
            SpringKeyframe(0, duration: SlideStyle.nudgeBack, spring: .smooth)
          }
          .offset(x: offset)
          .gesture(dragGesture(travel: travel), including: isEnabled && !confirmed ? .all : .none)
      }
      .sensoryFeedback(.selection, trigger: Int(progress * SlideStyle.ticks))
    }
    .frame(height: height)
    .opacity(isEnabled ? 1 : NessaMotion.disabledOpacity)
    .sensoryFeedback(.impact(weight: .heavy), trigger: confirmed) { _, new in new }
    .sensoryFeedback(.selection, trigger: isArmed) { _, new in new }
    // Disarmed (after a confirm too), the knob goes home so the slide is ready to use again.
    .onChange(of: isArmed) { _, new in
      if new {
        if !reduceMotion { nudges += 1 }
      } else if confirmed {
        withAnimation(reduceMotion ? nil : SlideStyle.springBack) { confirmed = false }
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(isArmed ? label : restingLabel ?? label)
    .accessibilityAddTraits(.isButton)
    .accessibilityAction { isArmed ? confirm() : arm() }
  }

  private var knob: some View {
    NessaSlideKnob(symbol: symbol, tint: tint, diameter: height - SlideStyle.knobInset * 2)
      .scaleEffect(holding ? SlideStyle.liftScale : 1)
      .padding(SlideStyle.knobInset)
      .contentShape(Circle())
      .animation(reduceMotion ? nil : NessaMotion.press, value: holding)
  }

  /// One gesture serves both states: at rest a press is the button that arms the slide, and
  /// only an armed knob follows the finger.
  private func dragGesture(travel: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .updating($drag) { value, drag, _ in if isArmed { drag = value.translation.width } }
      .updating($holding) { _, holding, _ in holding = true }
      .onEnded { value in
        guard isArmed else {
          if abs(value.translation.width) < SlideStyle.tapSlop,
            abs(value.translation.height) < SlideStyle.tapSlop
          {
            arm()
          }
          return
        }
        // Short of the mark, the gesture state resets and the knob springs home on its own.
        if value.translation.width / travel >= SlideStyle.confirmAt { confirm() }
      }
  }

  private func arm() {
    guard isEnabled, let armed, !armed.wrappedValue else { return }
    withAnimation(reduceMotion ? nil : NessaMotion.morph) { armed.wrappedValue = true }
  }

  private func confirm() {
    guard isEnabled, !confirmed else { return }
    withAnimation(reduceMotion ? nil : NessaMotion.press) { confirmed = true }
    onConfirm()
  }
}

/// The tint pouring in behind the knob: solid up to it, deepening along its length and as
/// the knob nears the end. Progress is animatable, so on a spring back the width and the
/// depth drain together frame by frame.
private struct NessaSlideFill: View, Animatable {
  var progress: CGFloat
  let travel: CGFloat
  let height: CGFloat
  let tint: Color
  // Animatable's requirement is nonisolated while View is main-actor; a CGFloat is safe to
  // hand across.
  nonisolated var animatableData: CGFloat {
    get { progress }
    set { progress = newValue }
  }
  var body: some View {
    let depth = SlideStyle.fillStart + (SlideStyle.fillEnd - SlideStyle.fillStart) * progress
    Capsule()
      .fill(
        LinearGradient(
          colors: [tint.opacity(SlideStyle.fillStart), tint.opacity(depth)],
          startPoint: .leading, endPoint: .trailing)
      )
      .frame(width: progress * travel + height)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
  }
}

private enum SlideStyle {
  static let trackHeight: CGFloat = 56
  /// The knob sits this far inside the track on every side, whatever the track's height.
  static let knobInset: CGFloat = 4
  static let knobIcon = Font.system(size: 18, weight: .semibold)
  static let label = Font.system(size: 17, weight: .medium)
  /// The knob grows this much when picked up.
  static let liftScale: CGFloat = 1.04
  /// Let go past this share of the track and it confirms.
  static let confirmAt: CGFloat = 0.85
  /// The label is gone by the time the knob is this far along.
  static let labelFadeEnd: CGFloat = 0.45
  /// A selection tick each quarter of the way.
  static let ticks: CGFloat = 4
  static let springBack = Animation.spring(duration: 0.25, bounce: 0.15)
  /// How far the knob pushes toward the end when the slide arms, and how long it takes out
  /// and back.
  static let nudgeDistance: CGFloat = 10
  static let nudgeOut: TimeInterval = 0.1
  static let nudgeBack: TimeInterval = 0.18
  /// A press that moves less than this is a tap on the knob, not a drag.
  static let tapSlop: CGFloat = 10
  /// The fill's tint strength at the track's start, and at the knob once it reaches the end.
  static let fillStart: Double = 0.25
  static let fillEnd: Double = 0.85
}

/// The knob: the tint with the symbol in white.
private struct NessaSlideKnob: View {
  private let symbol: String
  private let tint: Color
  private let diameter: CGFloat
  init(symbol: String, tint: Color, diameter: CGFloat) {
    self.symbol = symbol
    self.tint = tint
    self.diameter = diameter
  }
  var body: some View {
    Circle().fill(tint)
      .overlay(
        Image(systemName: symbol).font(SlideStyle.knobIcon).foregroundStyle(NessaColor.foreground)
      )
      .frame(width: diameter, height: diameter)
  }
}
