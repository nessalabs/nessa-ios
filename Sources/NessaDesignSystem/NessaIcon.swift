import SwiftUI

/// Nessa's own line icons: one fine stroke on a 24-point grid, round ends, drawn in the
/// current foreground. Used where a system symbol's heavier, generic look would stand out
/// against the quiet ground (the home screen and the sidebar).
public enum NessaIconName: Sendable {
  /// Two lines, the lower one shorter: opens the sidebar.
  case menu
  /// A page with a pen: a new chat.
  case compose
  case plus
  case microphone
  /// A sound wave: talk instead of type.
  case wave
  case chevronDown
  /// Two overlapping speech bubbles: every chat.
  case chats
  /// A channel.
  case hash
  /// Four rounded squares: every agent at a glance.
  case agents
  case pin
  case search
}

public struct NessaIcon: View {
  private let name: NessaIconName
  private let size: CGFloat
  private let weight: CGFloat
  public init(_ name: NessaIconName, size: CGFloat = NessaIconStyle.size,
    weight: CGFloat = NessaIconStyle.stroke)
  {
    self.name = name
    self.size = size
    self.weight = weight
  }
  public var body: some View {
    NessaIconShape(name: name)
      .stroke(style: StrokeStyle(lineWidth: weight, lineCap: .round, lineJoin: .round))
      .frame(width: size, height: size)
      // Hit-tested as its square, not as its hairline strokes.
      .contentShape(Rectangle())
      .accessibilityHidden(true)
  }
}

public enum NessaIconStyle {
  public static let size: CGFloat = 22
  /// On the 24-point grid; scaled with the icon.
  public static let stroke: CGFloat = 1.4
}

/// The icon's path on a 24×24 grid, scaled to the frame it is given.
struct NessaIconShape: Shape {
  let name: NessaIconName
  func path(in rect: CGRect) -> Path {
    var p = Path()
    func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
      CGPoint(x: rect.minX + x / 24 * rect.width, y: rect.minY + y / 24 * rect.height)
    }
    func line(_ a: (CGFloat, CGFloat), _ b: (CGFloat, CGFloat)) {
      p.move(to: pt(a.0, a.1))
      p.addLine(to: pt(b.0, b.1))
    }
    let unit = rect.width / 24
    switch name {
    case .menu:
      line((4.5, 9), (19.5, 9))
      line((4.5, 15), (13.5, 15))
    case .compose:
      // The page, open at the top right where the pen comes in.
      p.move(to: pt(20, 12.5))
      p.addLine(to: pt(20, 18))
      p.addQuadCurve(to: pt(18, 20), control: pt(20, 20))
      p.addLine(to: pt(6, 20))
      p.addQuadCurve(to: pt(4, 18), control: pt(4, 20))
      p.addLine(to: pt(4, 6))
      p.addQuadCurve(to: pt(6, 4), control: pt(4, 4))
      p.addLine(to: pt(11.5, 4))
      // The pen.
      p.move(to: pt(17.6, 3.9))
      p.addLine(to: pt(20.1, 6.4))
      p.addLine(to: pt(12.5, 14))
      p.addLine(to: pt(9.5, 14.6))
      p.addLine(to: pt(10.1, 11.6))
      p.closeSubpath()
    case .plus:
      line((12, 5.5), (12, 18.5))
      line((5.5, 12), (18.5, 12))
    case .microphone:
      p.addRoundedRect(
        in: CGRect(origin: pt(9, 3.5), size: CGSize(width: 6 * unit, height: 11 * unit)),
        cornerSize: CGSize(width: 3 * unit, height: 3 * unit))
      p.move(to: pt(5.5, 11.5))
      p.addQuadCurve(to: pt(18.5, 11.5), control: pt(12, 24))
      line((12, 18.2), (12, 20.5))
    case .wave:
      for (x, h) in [(5.0, 2.5), (8.5, 6.0), (12.0, 9.0), (15.5, 5.0), (19.0, 2.0)] {
        line((x, 12 - h), (x, 12 + h))
      }
    case .chevronDown:
      p.move(to: pt(7, 10))
      p.addLine(to: pt(12, 15))
      p.addLine(to: pt(17, 10))
    case .chats:
      p.addRoundedRect(
        in: CGRect(origin: pt(3.5, 4), size: CGSize(width: 12 * unit, height: 9 * unit)),
        cornerSize: CGSize(width: 3 * unit, height: 3 * unit))
      p.move(to: pt(6.5, 13))
      p.addLine(to: pt(5.5, 16))
      p.addLine(to: pt(9.5, 13))
      p.move(to: pt(15.5, 8.5))
      p.addLine(to: pt(17.5, 8.5))
      p.addQuadCurve(to: pt(20.5, 11.5), control: pt(20.5, 8.5))
      p.addLine(to: pt(20.5, 14.5))
      p.addQuadCurve(to: pt(17.5, 17.5), control: pt(20.5, 17.5))
      p.addLine(to: pt(17.5, 20))
      p.addLine(to: pt(14.5, 17.5))
      p.addLine(to: pt(11.5, 17.5))
      p.addQuadCurve(to: pt(9, 15.5), control: pt(9, 17.5))
    case .hash:
      line((10, 4.5), (8, 19.5))
      line((16, 4.5), (14, 19.5))
      line((5, 9.5), (19.5, 9.5))
      line((4.5, 14.5), (19, 14.5))
    case .agents:
      for (x, y) in [(3.5, 3.5), (13.5, 3.5), (3.5, 13.5), (13.5, 13.5)] {
        p.addRoundedRect(
          in: CGRect(origin: pt(CGFloat(x), CGFloat(y)), size: CGSize(width: 7 * unit, height: 7 * unit)),
          cornerSize: CGSize(width: 2 * unit, height: 2 * unit))
      }
    case .pin:
      p.move(to: pt(9, 4))
      p.addLine(to: pt(15, 4))
      p.move(to: pt(10, 4))
      p.addLine(to: pt(10, 10))
      p.addLine(to: pt(7, 14))
      p.addLine(to: pt(17, 14))
      p.addLine(to: pt(14, 10))
      p.addLine(to: pt(14, 4))
      line((12, 14), (12, 20))
    case .search:
      p.addEllipse(in: CGRect(origin: pt(4.5, 4.5), size: CGSize(width: 11 * unit, height: 11 * unit)))
      line((14, 14), (19.5, 19.5))
    }
    return p
  }
}
