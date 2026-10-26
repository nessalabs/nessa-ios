import SwiftUI

/// The person's own disc: a head and shoulders drawn in the home screen's halftone light,
/// lit from below as the horizon is, so it reads as part of the same ground.
public struct NessaProfileDisc: View {
  private let size: CGFloat
  public init(size: CGFloat) { self.size = size }

  public var body: some View {
    Canvas { context, canvas in
      context.fill(Path(CGRect(origin: .zero, size: canvas)), with: .color(.black))
      let cell = ProfileDiscStyle.cell
      var dots = Path()
      var y: CGFloat = 0
      while y < canvas.height {
        var x: CGFloat = 0
        while x < canvas.width {
          let point = CGPoint(x: x + cell / 2, y: y + cell / 2)
          let d = Self.light(point, canvas)
          // As on the home screen: the dot's area follows the light, and specks are left out.
          let diameter = cell * 0.95 * d.squareRoot()
          if diameter > ProfileDiscStyle.smallestDot {
            dots.addEllipse(
              in: CGRect(
                x: x + (cell - diameter) / 2, y: y + (cell - diameter) / 2, width: diameter,
                height: diameter))
          }
          x += cell
        }
        y += cell
      }
      context.fill(dots, with: .color(MessagesStyle.channelLight))
    }
    .frame(width: size, height: size)
    .clipShape(Circle())
    .overlay(Circle().strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
    .accessibilityHidden(true)
  }

  /// How lit a point is: the figure full where the light reaches it, the ground around it
  /// only faintly, both brighter towards the bottom.
  static func light(_ p: CGPoint, _ s: CGSize) -> Double {
    let rise = max(0, min(1, 1.15 - p.y / s.height))
    let below = 0.35 + 0.65 * (1 - rise)
    return (figure(p, s) ? 1 : ProfileDiscStyle.ground) * below
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
  static let cell: CGFloat = 2.5
  static let smallestDot: CGFloat = 0.6
  /// How lit the ground around the figure is, next to the figure's 1.
  static let ground: Double = 0.18
}
