import SwiftUI

/// The travelling light on the composer's rim while the agent works: nessa_ui's
/// `PillComposerRim` `orbit` variant. A crisp band on the edge plus a blurred copy
/// bleeding inward as glow. It fades in and out with `active`, keeps turning until
/// the fade-out finishes so stopping reads as the light dimming, and stands still
/// under Reduce Motion or while the app is not in the foreground.
public struct NessaRim<S: InsettableShape>: ViewModifier {
  let active: Bool
  let shape: S
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @State private var present = false
  @State private var lit: Double = 0
  @State private var fade = 0
  @State private var startedAt = Date()

  public func body(content: Content) -> some View {
    content.overlay {
      // Kept in the tree and paused when unlit, so a fade has something to fade.
      TimelineView(
        .animation(
          minimumInterval: 1.0 / 60,
          paused: !present || reduceMotion || scenePhase != .active)
      ) { context in
        let turn = context.date.timeIntervalSince(startedAt) / NessaMotion.ambient
        let degrees = reduceMotion ? -90 : turn.truncatingRemainder(dividingBy: 1) * 360
        let light = AngularGradient(stops: Self.stops, center: .center, angle: .degrees(degrees))
        ZStack {
          shape.strokeBorder(light, lineWidth: 4).blur(radius: 6).opacity(0.7)
          shape.strokeBorder(light, lineWidth: 1.25)
        }
        .clipShape(shape)
      }
      .opacity(lit)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
    }
    .onChange(of: active, initial: true) { _, isActive in
      fade += 1
      let generation = fade
      if isActive {
        if !present { startedAt = Date() }
        present = true
        withAnimation(NessaMotion.standard(NessaMotion.slow)) { lit = 1 }
      } else {
        withAnimation(NessaMotion.standard(NessaMotion.slow)) {
          lit = 0
        } completion: {
          // A later change owns presence now; only the newest fade-out retires it.
          if fade == generation { present = false }
        }
      }
    }
  }

  /// The decaying trail: faint amber behind the head, building through pink and purple
  /// into cyan, then the white head and a sharp cutoff.
  private static var stops: [Gradient.Stop] {
    let rim = NessaColor.rim
    return [
      .init(color: rim[0], location: 0),
      .init(color: rim[1], location: 0.25),
      .init(color: rim[2], location: 0.5),
      .init(color: rim[3], location: 0.72),
      .init(color: rim[4], location: 0.89),
      .init(color: rim[5], location: 0.989),
      .init(color: .clear, location: 1),
    ]
  }
}

extension View {
  /// Lights the edge of `shape` while `active`.
  public func nessaRim<S: InsettableShape>(active: Bool, in shape: S) -> some View {
    modifier(NessaRim(active: active, shape: shape))
  }
}

/// A sheen that sweeps through text while something is in progress, in the thinking colours.
public struct NessaShimmer: ViewModifier {
  let active: Bool
  let base: Color
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @State private var startedAt = Date()
  public func body(content: Content) -> some View {
    if active && !reduceMotion {
      TimelineView(.animation(minimumInterval: 1.0 / 30, paused: scenePhase != .active)) {
        context in
        let period = NessaMotion.ambient * 0.6
        let t = context.date.timeIntervalSince(startedAt).truncatingRemainder(dividingBy: period)
          / period
        let center = -0.4 + 1.8 * t
        content.foregroundStyle(
          LinearGradient(
            stops: [
              .init(color: base, location: 0),
              .init(color: NessaColor.thinkingCurrent, location: 0.4),
              .init(color: NessaColor.thinkingHighlight, location: 0.5),
              .init(color: NessaColor.thinkingCurrent, location: 0.6),
              .init(color: base, location: 1),
            ],
            startPoint: UnitPoint(x: center - 0.45, y: 0.5),
            endPoint: UnitPoint(x: center + 0.45, y: 0.5)))
      }
    } else if active {
      content.foregroundStyle(NessaColor.thinkingCurrent)
    } else {
      content.foregroundStyle(base)
    }
  }
}

extension View {
  /// Sweeps a thinking-coloured sheen through the view's text while `active`.
  public func nessaShimmer(active: Bool, base: Color = NessaColor.mutedForeground) -> some View {
    modifier(NessaShimmer(active: active, base: base))
  }
}
