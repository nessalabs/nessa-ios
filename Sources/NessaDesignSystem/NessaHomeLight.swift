import SwiftUI

/// The home screen's ground: black, with one soft light on it, drawn in a dither. Each style
/// is a place the light falls (its shape) and a way of drawing it (its pattern).
public enum NessaHomeLightStyle: String, CaseIterable, Sendable {
  /// From the top trailing corner, a smooth falloff under a faint grain.
  case cornerLight
  /// A flat glow rising behind the composer, in halftone dots: the default.
  case horizon
  /// Straight down from the top, in an ordered pixel dither.
  case spotlight
  /// A band across the screen, in fine scanlines.
  case diagonal
  /// The accent, faint, from the top leading corner, under a fine grain.
  case blueHour
  /// A ring around the greeting, in halftone dots.
  case eclipse
}

public struct NessaHomeLight: View {
  private let style: NessaHomeLightStyle
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  /// Whether the ground is on screen: a pushed screen covers it but keeps it alive.
  @State private var onScreen = false
  /// Whether the light has risen: it comes up once when the app opens, not on every return.
  @State private var risen = false
  public init(style: NessaHomeLightStyle = .horizon) { self.style = style }

  public var body: some View {
    // Only the horizon's dots drift, and only while someone can see them.
    let moving = style == .horizon && !reduceMotion && scenePhase == .active && onScreen
    ZStack {
      Color.black
      ZStack {
        // The glow never moves, so it is drawn once rather than on every frame of the drift.
        Canvas { context, size in ground(context, size) }
        TimelineView(.animation(minimumInterval: HomeLightStyle.frameInterval, paused: !moving)) {
          timeline in
          let time = moving ? timeline.date.timeIntervalSinceReferenceDate : 0
          Canvas { context, size in pattern(context, size, time: time) }
        }
      }
      // Moved and faded as a whole, so the rise costs no redraw.
      .offset(y: risen ? 0 : HomeLightStyle.riseDistance)
      .opacity(risen ? 1 : 0)
    }
    .ignoresSafeArea()
    .allowsHitTesting(false)
    .accessibilityHidden(true)
    .onAppear {
      onScreen = true
      guard !risen else { return }
      withAnimation(reduceMotion ? nil : HomeLightStyle.rise) { risen = true }
    }
    .onDisappear { onScreen = false }
  }

  private func ground(_ context: GraphicsContext, _ size: CGSize) {
    // The smooth light under the pattern, so the dither reads as texture on a glow rather
    // than as dots on black.
    Self.glow(
      context, size, shape: Self.shape(style), color: Self.ink(style), strength: Self.glow(style))
  }

  private func pattern(_ context: GraphicsContext, _ size: CGSize, time: TimeInterval) {
    let shape = Self.shape(style)
    switch style {
    case .cornerLight, .blueHour:
      Self.grain(context, size, shape: shape, color: Self.ink(style))
    case .horizon:
      // Softer under the horizon, where the composer's text sits on it; its dots swell and
      // shrink in slow waves, so the light seems to breathe.
      Self.halftone(
        context, size, shape: Self.drifting(shape, time: time),
        color: Self.ink(style).opacity(0.6), from: size.height * (1 - Self.horizonReach))
    case .eclipse:
      Self.halftone(context, size, shape: shape, color: Self.ink(style))
    case .spotlight:
      Self.pixels(context, size, shape: shape, color: Self.ink(style))
    case .diagonal:
      Self.scanlines(context, size, shape: shape, color: Self.ink(style))
    }
  }

  /// How far up the screen the horizon's light reaches, as a share of its height.
  static let horizonReach: CGFloat = 0.56

  /// The light, rippled by two slow waves crossing each other: at most a few percent either
  /// way, so it reads as texture moving rather than the light changing.
  static func drifting(_ shape: @escaping Shape, time: TimeInterval) -> Shape {
    guard time != 0 else { return shape }
    let t = time.truncatingRemainder(dividingBy: HomeLightStyle.driftPeriod)
    return { p, s in
      let wave = sin(p.x / HomeLightStyle.driftLength + t * HomeLightStyle.driftSpeed)
        * cos(p.y / (HomeLightStyle.driftLength * 0.7) - t * HomeLightStyle.driftSpeed * 0.7)
      return min(1, shape(p, s) * (1 + HomeLightStyle.driftDepth * wave))
    }
  }

  /// How strongly the light falls on a point, from 0 to 1.
  typealias Shape = (CGPoint, CGSize) -> Double

  static func shape(_ style: NessaHomeLightStyle) -> Shape {
    switch style {
    case .cornerLight:
      return { p, s in ellipse(p, centre: CGPoint(x: s.width, y: 0), rx: s.width * 1.3 * 0.66,
        ry: s.height * 0.75 * 0.66) }
    case .blueHour:
      return { p, s in ellipse(p, centre: .zero, rx: s.width * 1.2 * 0.66, ry: s.height * 0.7 * 0.66) }
    case .horizon:
      return { p, s in
        // A wide, flat glow along the bottom: mostly how far up the screen, barely how far
        // from the middle, so it reads as a horizon rather than a disc.
        let linear = max(0, 1 - (s.height - p.y) / (s.height * horizonReach))
        // Eased in, so the light has no edge where it starts.
        let rise = linear * linear * (3 - 2 * linear)
        let side = abs(p.x - s.width / 2) / (s.width / 2)
        return pow(rise, 1.6) * (1 - 0.25 * side * side)
      }
    case .spotlight:
      return { p, s in ellipse(p, centre: CGPoint(x: s.width / 2, y: 0), rx: s.width * 0.7 * 0.86,
        ry: s.height * 0.62 * 0.86) }
    case .diagonal:
      return { p, s in
        // Distance from a line falling from the top trailing side to the leading middle.
        let along = (p.x * 0.34 + p.y * 0.94) / s.height
        return max(0, 1 - abs(along - 0.36) / 0.2)
      }
    case .eclipse:
      return { p, s in
        let centre = CGPoint(x: s.width / 2, y: s.height * 0.45)
        let r: CGFloat = hypot(p.x - centre.x, p.y - centre.y)
        guard r > HomeLightStyle.eclipseRadius else { return 0 }
        let strength: CGFloat =
          max(0, 1 - (r - HomeLightStyle.eclipseRadius) / HomeLightStyle.eclipseSpread)
        return Double(strength)
      }
    }
  }

  private static func ellipse(_ p: CGPoint, centre: CGPoint, rx: CGFloat, ry: CGFloat) -> Double {
    let dx = (p.x - centre.x) / rx
    let dy = (p.y - centre.y) / ry
    return pow(max(0, 1 - (dx * dx + dy * dy).squareRoot()), 1.5)
  }

  private static func ink(_ style: NessaHomeLightStyle) -> Color {
    style == .blueHour ? NessaColor.accent : HomeLightStyle.light
  }

  private static func glow(_ style: NessaHomeLightStyle) -> Double {
    switch style {
    case .cornerLight: return 0.6
    case .blueHour: return 0.34
    case .spotlight, .eclipse: return 0.3
    case .horizon, .diagonal: return 0.2
    }
  }

  private static func glow(
    _ context: GraphicsContext, _ size: CGSize, shape: Shape, color: Color, strength: Double
  ) {
    // Coarse cells blurred together: a smooth light for the cost of a few hundred fills.
    context.drawLayer { layer in
      layer.addFilter(.blur(radius: HomeLightStyle.glowCell))
      forEachCell(size, cell: HomeLightStyle.glowCell) { _, _, point in
        let d = shape(point, size)
        guard d > 0.01 else { return }
        layer.fill(
          Path(
            CGRect(
              origin: point,
              size: CGSize(width: HomeLightStyle.glowCell, height: HomeLightStyle.glowCell))),
          with: .color(color.opacity(strength * d)))
      }
    }
  }

  private static func grain(_ context: GraphicsContext, _ size: CGSize, shape: Shape, color: Color) {
    var dots = Path()
    forEachCell(size, cell: HomeLightStyle.grainCell) { column, row, point in
      guard threshold(column, row) < 0.6 * shape(point, size) + 0.08 else { return }
      dots.addEllipse(in: CGRect(origin: point, size: CGSize(width: 1, height: 1)))
    }
    context.fill(dots, with: .color(color.opacity(0.35)))
  }

  private static func halftone(
    _ context: GraphicsContext, _ size: CGSize, shape: Shape, color: Color, from top: CGFloat = 0
  ) {
    var dots = Path()
    let cell = HomeLightStyle.halftoneCell
    forEachCell(size, cell: cell, from: top) { _, _, point in
      let d = shape(CGPoint(x: point.x + cell / 2, y: point.y + cell / 2), size)
      // The dot's area, not its width, follows the light, as in print; the faintest dots are
      // left out rather than drawn as specks, so the light's edge feathers instead of stepping.
      let diameter = cell * 0.9 * d.squareRoot()
      guard diameter > HomeLightStyle.smallestDot else { return }
      dots.addEllipse(
        in: CGRect(
          x: point.x + (cell - diameter) / 2, y: point.y + (cell - diameter) / 2,
          width: diameter, height: diameter))
    }
    context.fill(dots, with: .color(color.opacity(0.85)))
  }

  /// The 4×4 Bayer matrix, as thresholds between 0 and 1.
  private static let bayer: [Double] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
    .map { ($0 + 0.5) / 16 }

  private static func pixels(_ context: GraphicsContext, _ size: CGSize, shape: Shape, color: Color)
  {
    var pixels = Path()
    let cell = HomeLightStyle.pixelCell
    forEachCell(size, cell: cell) { column, row, point in
      guard shape(point, size) > bayer[(row % 4) * 4 + column % 4] else { return }
      pixels.addRect(CGRect(origin: point, size: CGSize(width: cell, height: cell)))
    }
    context.fill(pixels, with: .color(color.opacity(0.75)))
  }

  private static func scanlines(
    _ context: GraphicsContext, _ size: CGSize, shape: Shape, color: Color
  ) {
    let cell = HomeLightStyle.scanlineSegment
    var y: CGFloat = 0
    while y < size.height {
      var x: CGFloat = 0
      while x < size.width {
        let d = shape(CGPoint(x: x, y: y), size)
        if d > 0.01 {
          context.fill(
            Path(CGRect(x: x, y: y, width: cell, height: 1)),
            with: .color(color.opacity(0.7 * d)))
        }
        x += cell
      }
      y += HomeLightStyle.scanlinePitch
    }
  }

  /// Every cell of a grid over the canvas, from row `top` down: a light that never reaches
  /// higher costs nothing above it.
  private static func forEachCell(
    _ size: CGSize, cell: CGFloat, from top: CGFloat = 0, _ body: (Int, Int, CGPoint) -> Void
  ) {
    let columns = Int((size.width / cell).rounded(.up))
    let rows = Int((size.height / cell).rounded(.up))
    for row in max(0, Int(top / cell))..<max(rows, 0) {
      for column in 0..<columns {
        body(column, row, CGPoint(x: CGFloat(column) * cell, y: CGFloat(row) * cell))
      }
    }
  }

  /// A fixed pseudo-random threshold per cell, the same on every draw.
  private static func threshold(_ x: Int, _ y: Int) -> Double {
    var h = UInt32(truncatingIfNeeded: x &* 374_761_393 &+ y &* 668_265_263)
    h = (h ^ (h >> 13)) &* 1_274_126_177
    h ^= h >> 16
    return Double(h & 0xFFFF) / 65_535
  }
}

enum HomeLightStyle {
  /// The light itself: a warm grey, the one tint on the ground besides the accent.
  static let light = Color(hex: 0xD6D2CE)
  static let glowCell: CGFloat = 24
  static let grainCell: CGFloat = 3
  static let halftoneCell: CGFloat = 5
  /// Dots smaller than this are not drawn.
  static let smallestDot: CGFloat = 1.1
  static let pixelCell: CGFloat = 2
  static let scanlinePitch: CGFloat = 3
  static let scanlineSegment: CGFloat = 6
  /// The dark disc the eclipse ring leaves around the greeting, and how far the ring fades.
  static let eclipseRadius: CGFloat = 100
  static let eclipseSpread: CGFloat = 140
  /// The horizon's drift: how far its dots swell either way, how long its waves are in
  /// points, and how fast they move in radians a second. Slow on purpose: a wave takes about
  /// twelve seconds to pass.
  static let driftDepth: Double = 0.24
  static let driftLength: CGFloat = 60
  static let driftSpeed: Double = 0.5
  /// The time the drift's phase wraps at, so its sums stay precise however long the app runs:
  /// a whole number of turns of both waves (10 at 0.5 rad/s, 7 at 0.35), so the wrap is unseen.
  static let driftPeriod: TimeInterval = 40 * .pi
  /// The drift redraws at most this often: smooth for something this slow, at under half the
  /// work of every display frame.
  static let frameInterval: TimeInterval = 1.0 / 24
  /// The light coming up from below when the app opens: seen once a launch, so it may take
  /// its time, as the motion guide allows a rare moment. Reduce Motion shows it at once.
  static let rise = Animation.easeOut(duration: 1.1)
  static let riseDistance: CGFloat = 120
}
