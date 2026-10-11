import SwiftUI

/// Custom heart artwork, native emoji, and shared lettering for Messages Tapbacks.
public struct TapbackSymbol: View {
  public let value: String
  public init(value: String) { self.value = value }
  public var body: some View {
    Group {
      switch value {
      case "❤️": TapbackHeart()
      case "👍", "👎": Text(value).font(MessagesStyle.reactionEmojiFont)
      case "😂":
        Text("HA\nHA").font(MessagesStyle.tapbackLetters).lineSpacing(-4)
          .foregroundStyle(
            LinearGradient(
              colors: [MessagesStyle.tapbackCyanLight, MessagesStyle.tapbackCyan], startPoint: .top,
              endPoint: .bottom))
      case "‼️": letters("!!", top: MessagesStyle.tapbackRedLight, bottom: MessagesStyle.tapbackRed)
      case "❓":
        letters("?", top: MessagesStyle.tapbackPurpleLight, bottom: MessagesStyle.tapbackPurple)
      default: Text(value).font(MessagesStyle.reactionFont)
      }
    }.shadow(color: MessagesStyle.background.opacity(0.25), radius: 1, y: 2)
      .accessibilityHidden(true)
  }
  private func letters(_ text: String, top: Color, bottom: Color) -> some View {
    Text(text).font(MessagesStyle.tapbackPunctuation)
      .foregroundStyle(LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom))
  }
}

public struct TapbackBadge: View {
  public let value: String
  public init(value: String) { self.value = value }
  public var body: some View {
    ZStack(alignment: .topLeading) {
      TapbackThoughtShape().fill(MessagesStyle.tapbackBackground)
      TapbackSymbol(value: value).scaleEffect(MessagesStyle.tapbackBadgeScale)
        .frame(width: MessagesStyle.tapbackBadgeCircle, height: MessagesStyle.tapbackBadgeCircle)
    }.frame(width: MessagesStyle.tapbackBadgeWidth, height: MessagesStyle.tapbackBadgeHeight)
  }
}

/// Vector artwork stays sharp in both the picker and the smaller applied badge.
private struct TapbackHeart: View {
  var body: some View {
    HeartShape().fill(
      LinearGradient(
        colors: [MessagesStyle.tapbackPinkLight, MessagesStyle.tapbackPink],
        startPoint: .top, endPoint: .bottom)
    ).overlay {
      GeometryReader { geometry in
        Ellipse().fill(MessagesStyle.tapbackHeartHighlight)
          .frame(width: geometry.size.width * 0.27, height: geometry.size.height * 0.12)
          .rotationEffect(.degrees(-30))
          .position(x: geometry.size.width * 0.25, y: geometry.size.height * 0.22)
          .blur(radius: 1)
        Ellipse().fill(MessagesStyle.tapbackHeartHighlight.opacity(0.55))
          .frame(width: geometry.size.width * 0.23, height: geometry.size.height * 0.10)
          .rotationEffect(.degrees(25))
          .position(x: geometry.size.width * 0.74, y: geometry.size.height * 0.21)
          .blur(radius: 1)
      }.clipShape(HeartShape())
    }.frame(width: MessagesStyle.tapbackHeartSize, height: MessagesStyle.tapbackHeartSize)
  }
}

private struct HeartShape: Shape {
  func path(in rect: CGRect) -> Path {
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
      CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
    }
    var path = Path()
    path.move(to: point(0.5, 0.94))
    path.addCurve(to: point(0.02, 0.32), control1: point(0.36, 0.82), control2: point(0.02, 0.60))
    path.addCurve(to: point(0.5, 0.20), control1: point(0.02, 0.02), control2: point(0.34, 0.01))
    path.addCurve(to: point(0.98, 0.32), control1: point(0.66, 0.01), control2: point(0.98, 0.02))
    path.addCurve(to: point(0.5, 0.94), control1: point(0.98, 0.60), control2: point(0.64, 0.82))
    path.closeSubpath()
    return path
  }
}

private struct TapbackThoughtShape: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    let circle = min(rect.width * 0.81, rect.height * 0.71)
    path.addEllipse(in: CGRect(x: 0, y: 0, width: circle, height: circle))
    path.addEllipse(
      in: CGRect(x: circle * 0.70, y: circle * 0.80, width: circle * 0.28, height: circle * 0.28))
    path.addEllipse(
      in: CGRect(x: circle * 1.02, y: circle * 1.22, width: circle * 0.13, height: circle * 0.13))
    return path
  }
}

/// The additional-reaction control uses the same thought-bubble silhouette as Tapbacks.
public struct TapbackMoreSymbol: View {
  public init() {}
  public var body: some View {
    ZStack {
      Circle().fill(MessagesStyle.control)
        .frame(width: MessagesStyle.tapbackMoreCircle, height: MessagesStyle.tapbackMoreCircle)
      Image(systemName: "face.smiling.fill").font(MessagesStyle.reactionSelectorFace)
        .foregroundStyle(MessagesStyle.secondary)
      Circle().fill(MessagesStyle.control)
        .frame(width: MessagesStyle.tapbackMoreTrail, height: MessagesStyle.tapbackMoreTrail)
        .offset(x: NessaSpacing.md, y: NessaSpacing.md)
      Circle().fill(MessagesStyle.control)
        .frame(width: MessagesStyle.tapbackMoreDot, height: MessagesStyle.tapbackMoreDot)
        .offset(x: NessaSpacing.lg, y: NessaSpacing.lg)
    }.frame(
      width: MessagesStyle.reactionPaletteControl, height: MessagesStyle.reactionPaletteControl
    )
    .accessibilityHidden(true)
  }
}

/// Reserve clearance above reacted content; the badge lives outside its bubble.
public struct MessagesTapbackPlacement: ViewModifier {
  public let value: String?
  public let outgoing: Bool
  public func body(content: Content) -> some View {
    content.overlay(alignment: outgoing ? .topLeading : .topTrailing) {
      if let value {
        TapbackBadge(value: value)
          .offset(
            x: outgoing
              ? MessagesStyle.reactionHorizontalOffset - MessagesStyle.tapbackBadgeCircle / 2
              : MessagesStyle.tapbackBadgeWidth - MessagesStyle.tapbackBadgeCircle / 2
                - MessagesStyle.reactionHorizontalOffset,
            y: MessagesStyle.reactionOffset
          )
          .accessibilityLabel("Reaction: \(value)")
      }
    }.padding(.top, value == nil ? 0 : MessagesStyle.reactionClearance)
  }
}
extension View {
  public func messagesTapback(_ value: String?, outgoing: Bool) -> some View {
    modifier(MessagesTapbackPlacement(value: value, outgoing: outgoing))
  }
}
