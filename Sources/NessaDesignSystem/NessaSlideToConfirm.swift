import SwiftUI

/// A deliberate confirm: pick up the knob and slide it to the end of the track, like the old
/// slide to unlock. Behind the knob the track fills with dither pixels, sparse at the start
/// and dense at the knob, warming to the tint over the last stretch. Let go early and the
/// knob springs back and the pixels drain with it.
public struct NessaSlideToConfirm: View {
  private let label: String
  private let symbol: String
  private let tint: Color
  private let onConfirm: () -> Void
  @Environment(\.isEnabled) private var isEnabled
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// The live drag lives in gesture state, so a drag the system cancels (the sheet taking the
  /// pan, a second touch) springs back just like one let go early, instead of sticking.
  @GestureState(resetTransaction: Transaction(animation: SlideStyle.springBack))
  private var drag: CGFloat = 0
  @GestureState private var holding = false
  @State private var confirmed = false

  public init(
    _ label: String, symbol: String = "trash", tint: Color = NessaColor.destructive,
    onConfirm: @escaping () -> Void
  ) {
    self.label = label
    self.symbol = symbol
    self.tint = tint
    self.onConfirm = onConfirm
  }

  public var body: some View {
    GeometryReader { geometry in
      let travel = max(geometry.size.width - SlideStyle.trackHeight, 1)
      let offset = confirmed ? travel : min(max(drag, 0), travel)
      let progress = offset / travel
      ZStack(alignment: .leading) {
        Capsule().fill(NessaColor.muted)
          .overlay(Capsule().strokeBorder(NessaColor.hairline, lineWidth: 1))
        Text(label).font(SlideStyle.label)
          .nessaShimmer(active: isEnabled && !holding)
          .frame(maxWidth: .infinity)
          .padding(.leading, SlideStyle.trackHeight)
          .opacity(1 - min(progress / SlideStyle.labelFadeEnd, 1))
        NessaDitherFill(progress: progress, travel: travel, tint: tint)
        knob
          .offset(x: offset)
          .gesture(dragGesture(travel: travel), including: isEnabled && !confirmed ? .all : .none)
      }
      .sensoryFeedback(.selection, trigger: Int(progress * SlideStyle.ticks))
    }
    .frame(height: SlideStyle.trackHeight)
    .opacity(isEnabled ? 1 : NessaMotion.disabledOpacity)
    .sensoryFeedback(.impact(weight: .heavy), trigger: confirmed) { _, new in new }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(label)
    .accessibilityAddTraits(.isButton)
    .accessibilityAction { confirm() }
  }

  private var knob: some View {
    Circle().fill(NessaColor.foreground)
      .overlay(
        Image(systemName: symbol).font(SlideStyle.knobIcon)
          .foregroundStyle(confirmed ? tint : NessaColor.background)
      )
      .frame(width: SlideStyle.knobSize, height: SlideStyle.knobSize)
      .scaleEffect(holding ? SlideStyle.liftScale : 1)
      .padding((SlideStyle.trackHeight - SlideStyle.knobSize) / 2)
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

/// Ordered dither, the header grain's family: each 2 pt pixel lights when the fill's local
/// density passes its place in a 4×4 Bayer matrix, so the fill thickens toward the knob
/// without noise or banding. Progress is animatable, so on a spring back the width and the
/// warmth drain together frame by frame.
private struct NessaDitherFill: View, Animatable {
  var progress: CGFloat
  let travel: CGFloat
  let tint: Color
  // Animatable's requirement is nonisolated while View is main-actor; a CGFloat is safe to
  // hand across.
  nonisolated var animatableData: CGFloat {
    get { progress }
    set { progress = newValue }
  }
  private static let bayer: [Double] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
  var body: some View {
    let warmth = max(0, (progress - SlideStyle.warmFrom) / (1 - SlideStyle.warmFrom))
    Canvas { context, size in
      let cell = SlideStyle.pixel
      let columns = Int((size.width / cell).rounded(.up))
      let rows = Int((size.height / cell).rounded(.up))
      var path = Path()
      for column in 0..<columns {
        let along = Double(column) / Double(max(columns - 1, 1))
        let density = SlideStyle.peakDensity * pow(along, SlideStyle.rampCurve)
        for row in 0..<rows {
          let threshold = (Self.bayer[(row % 4) * 4 + column % 4] + 0.5) / 16
          if density > threshold {
            path.addRect(
              CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell))
          }
        }
      }
      context.fill(path, with: .color(NessaColor.foreground.mix(with: tint, by: warmth)))
    }
    .frame(width: progress * travel + SlideStyle.trackHeight)
    .clipShape(Capsule())
    .opacity(SlideStyle.fillOpacity)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

private enum SlideStyle {
  static let trackHeight: CGFloat = 56
  static let knobSize: CGFloat = 48
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
  static let springBack = Animation.spring(duration: 0.35, bounce: 0.25)
  static let pixel: CGFloat = 2
  static let peakDensity: Double = 0.92
  static let rampCurve: Double = 1.4
  /// Past this share the pixels warm from white toward the tint.
  static let warmFrom: CGFloat = 0.7
  static let fillOpacity: Double = 0.85
}
