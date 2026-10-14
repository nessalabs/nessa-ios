import SwiftUI

/// A deliberate confirm: pick up the knob and slide it to the end of the track, like the old
/// slide to unlock. The knob is the tint, and behind it the track fills with the tint, faint
/// at the start and deepening toward the knob and toward the end. Let go early and the knob
/// springs back and the fill drains with it.
public struct NessaSlideToConfirm: View {
  private let label: String
  private let symbol: String
  private let tint: Color
  private let height: CGFloat
  private let knobMatch: NessaMatch?
  private let onConfirm: () -> Void
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// The live drag lives in gesture state, so a drag the system cancels (the sheet taking the
  /// pan, a second touch) springs back just like one let go early, instead of sticking.
  @GestureState(resetTransaction: Transaction(animation: SlideStyle.springBack))
  private var drag: CGFloat = 0
  @GestureState private var holding = false
  @State private var confirmed = false

  /// `height` sizes the track, so it can stand in for a bar of the same height; the knob
  /// keeps the same inset at any height. `knobMatch` lets a button elsewhere turn into the
  /// knob: give that button the same match and swap the two in one animation.
  public init(
    _ label: String, symbol: String = "trash", tint: Color = NessaColor.destructive,
    height: CGFloat? = nil, knobMatch: NessaMatch? = nil, onConfirm: @escaping () -> Void
  ) {
    self.label = label
    self.symbol = symbol
    self.tint = tint
    self.height = height ?? SlideStyle.trackHeight
    self.knobMatch = knobMatch
    self.onConfirm = onConfirm
  }

  public var body: some View {
    GeometryReader { geometry in
      let travel = max(geometry.size.width - height, 1)
      let offset = confirmed ? travel : min(max(drag, 0), travel)
      let progress = offset / travel
      ZStack(alignment: .leading) {
        Capsule().fill(NessaColor.muted)
          .overlay(Capsule().strokeBorder(NessaColor.hairline, lineWidth: 1))
        Text(label).font(SlideStyle.label)
          .nessaShimmer(active: isEnabled && !holding)
          .frame(maxWidth: .infinity)
          .padding(.leading, height)
          .opacity(1 - min(progress / SlideStyle.labelFadeEnd, 1))
        NessaSlideFill(progress: progress, travel: travel, height: height, tint: tint)
        knob
          .offset(x: offset)
          .gesture(dragGesture(travel: travel), including: isEnabled && !confirmed ? .all : .none)
      }
      .sensoryFeedback(.selection, trigger: Int(progress * SlideStyle.ticks))
    }
    .frame(height: height)
    .opacity(isEnabled ? 1 : NessaMotion.disabledOpacity)
    .sensoryFeedback(.impact(weight: .heavy), trigger: confirmed) { _, new in new }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(label)
    .accessibilityAddTraits(.isButton)
    .accessibilityAction { confirm() }
  }

  private var knob: some View {
    NessaSlideKnob(symbol: symbol, tint: tint, diameter: height - SlideStyle.knobInset * 2)
      .nessaMatched(knobMatch)
      .scaleEffect(holding ? SlideStyle.liftScale : 1)
      .padding(SlideStyle.knobInset)
      .contentShape(Circle())
      .animation(reduceMotion ? nil : NessaMotion.press, value: holding)
  }

  private func dragGesture(travel: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .updating($drag) { value, drag, _ in drag = value.translation.width }
      .updating($holding) { _, holding, _ in holding = true }
      .onEnded { value in
        // Short of the mark, the gesture state resets and the knob springs home on its own.
        if value.translation.width / travel >= SlideStyle.confirmAt { confirm() }
      }
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
  /// The fill's tint strength at the track's start, and at the knob once it reaches the end.
  static let fillStart: Double = 0.25
  static let fillEnd: Double = 0.85
}

/// The knob: the tint with the symbol in white. Public so a button can wear the same face
/// before it turns into the knob.
public struct NessaSlideKnob: View {
  private let symbol: String
  private let tint: Color
  private let diameter: CGFloat
  public init(symbol: String = "trash", tint: Color = NessaColor.destructive, diameter: CGFloat) {
    self.symbol = symbol
    self.tint = tint
    self.diameter = diameter
  }
  public var body: some View {
    Circle().fill(tint)
      .overlay(
        Image(systemName: symbol).font(SlideStyle.knobIcon).foregroundStyle(NessaColor.foreground)
      )
      .frame(width: diameter, height: diameter)
  }
}

/// One shared geometry: the same id in the same namespace on two views that swap.
public struct NessaMatch {
  public let id: String
  public let namespace: Namespace.ID
  public init(id: String, in namespace: Namespace.ID) {
    self.id = id
    self.namespace = namespace
  }
}

extension View {
  @ViewBuilder public func nessaMatched(_ match: NessaMatch?) -> some View {
    if let match {
      matchedGeometryEffect(id: match.id, in: match.namespace)
    } else {
      self
    }
  }
}
