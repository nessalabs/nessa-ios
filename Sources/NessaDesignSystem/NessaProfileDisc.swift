import SwiftUI

/// The person's own disc: a head and shoulders drawn in the home screen's halftone light,
/// lit from below as the horizon is, so it reads as part of the same ground.
public struct NessaProfileDisc: View {
  private let size: CGFloat
  public init(size: CGFloat) { self.size = size }

  public var body: some View {
    Canvas { context, canvas in
      NessaHalftone.fill(
        context, canvas, cell: ProfileDiscStyle.cell, smallestDot: ProfileDiscStyle.smallestDot,
        color: MessagesStyle.channelLight
      ) { p in Self.light(p, canvas) }
    }
    .frame(width: size, height: size)
    .clipShape(Circle())
    .overlay(Circle().strokeBorder(MessagesStyle.litRim, lineWidth: 0.5))
    .accessibilityHidden(true)
  }

  /// How lit a point is: the figure full where the light reaches it, the ground around it
  /// only faintly, both brighter towards the bottom. The dimmest ground, at the top, still
  /// draws dots (`ProfileDiscStyle.topLight`), so the disc reads as a whole circle rather than
  /// one whose top is missing.
  static func light(_ p: CGPoint, _ s: CGSize) -> Double {
    let rise = max(0, min(1, 1.15 - p.y / s.height))
    let below = ProfileDiscStyle.topLight + (1 - ProfileDiscStyle.topLight) * (1 - rise)
    // The figure keeps most of its light to the top of the head, so its crown stays round.
    if figure(p, s) {
      return ProfileDiscStyle.figureTop + (1 - ProfileDiscStyle.figureTop) * below
    }
    return ProfileDiscStyle.ground * below
  }

  /// Whether a point is on the head or the shoulders.
  static func figure(_ p: CGPoint, _ s: CGSize) -> Bool {
    let head = CGPoint(x: s.width / 2, y: s.height * 0.4)
    if hypot(p.x - head.x, p.y - head.y) < s.width * 0.18 { return true }
    let shoulders = CGPoint(x: s.width / 2, y: s.height * 1.02)
    let dx = (p.x - shoulders.x) / (s.width * 0.36)
    let dy = (p.y - shoulders.y) / (s.height * 0.36)
    return dx * dx + dy * dy < 1
  }
}

enum ProfileDiscStyle {
  static let cell: CGFloat = 2
  static let smallestDot: CGFloat = 0.6
  /// How lit the ground around the figure is, next to the figure's 1.
  static let ground: Double = 0.18
  /// How much of the light reaches the top of the disc, next to 1 at its foot. With `ground`
  /// it keeps the top's dots above `smallestDot`, which the halftone leaves out.
  static let topLight: Double = 0.7
  /// The least light on the figure, at the top of the head, next to 1 at its shoulders.
  static let figureTop: Double = 0.7
}
