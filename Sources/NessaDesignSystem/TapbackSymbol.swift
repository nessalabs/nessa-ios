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
        // Mirrored gloss, so neither lobe reads heavier and pulls the heart off centre.
        ForEach([-1.0, 1.0], id: \.self) { side in
          Ellipse().fill(MessagesStyle.tapbackHeartHighlight)
            .frame(width: geometry.size.width * 0.25, height: geometry.size.height * 0.11)
            .rotationEffect(.degrees(30 * side))
            .position(
              x: geometry.size.width * (0.5 + 0.25 * side), y: geometry.size.height * 0.28)
            .blur(radius: 1)
        }
      }.clipShape(HeartShape())
    }.frame(width: MessagesStyle.tapbackHeartSize, height: MessagesStyle.tapbackHeartSize)
  }
}

/// Drawn so the heart's visual centre, the middle of its area rather than of its box, sits at
/// the middle of the frame. A heart's weight is in its two lobes, so a box-centred heart reads
/// as riding high inside its badge.
private struct HeartShape: Shape {
  func path(in rect: CGRect) -> Path {
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
      CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
    }
    var path = Path()
    path.move(to: point(0.5, 1.0))
    path.addCurve(to: point(0.02, 0.38), control1: point(0.36, 0.88), control2: point(0.02, 0.66))
    path.addCurve(to: point(0.5, 0.26), control1: point(0.02, 0.08), control2: point(0.34, 0.07))
    path.addCurve(to: point(0.98, 0.38), control1: point(0.66, 0.07), control2: point(0.98, 0.08))
    path.addCurve(to: point(0.5, 1.0), control1: point(0.98, 0.66), control2: point(0.64, 0.88))
    path.closeSubpath()
    return path
  }
}

private struct TapbackThoughtShape: Shape {
  func path(in rect: CGRect) -> Path {
    var path = Path()
    // The symbol is centred on this same circle, so both read its size from one token.
    let circle = MessagesStyle.tapbackBadgeCircle
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
