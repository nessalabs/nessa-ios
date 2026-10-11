import SwiftUI

/// Measurements in points, taken from the 440-point-wide Messages references.
public enum MessagesStyle {
  public static let pinAction = Color(hex: 0xFF9F0A)
  public static let archiveAction = Color(hex: 0x5856D6)
  public static let tapbackPinkLight = Color(hex: 0xFFB3DB)
  public static let tapbackPink = Color(hex: 0xFA3A96)
  public static let tapbackBackground = Color(hex: 0x18A4ED)
  public static let tapbackHeartSize: CGFloat = 28
  public static let tapbackHeartHighlight = Color.white.opacity(0.65)
  public static let photoSwipeTilt = 8.0
  public static let photoSwipeLift: CGFloat = 0.04
  public static let photoSwipeThreshold: CGFloat = 0.18
  public static let photoSwipeVelocity: CGFloat = 500
  public static let photoSwipeProjection: CGFloat = 0.12
  public static let photoSwipeExit: CGFloat = 1.3
  public static let photoSwipeAnimation = Animation.easeOut(duration: 0.20)
  public static let photoSwipeReturnAnimation = Animation.spring(duration: 0.25, bounce: 0.12)
  public static let tapbackYellowLight = Color(hex: 0xFFDD78)
  public static let tapbackYellow = Color(hex: 0xFCA728)
  public static let tapbackCyanLight = Color(hex: 0x79E8FF)
  public static let tapbackCyan = Color(hex: 0x009DEB)
  public static let tapbackRedLight = Color(hex: 0xFFAD96)
  public static let tapbackRed = Color(hex: 0xFF4138)
  public static let tapbackPurpleLight = Color(hex: 0xD8B1FF)
  public static let tapbackPurple = Color(hex: 0x9761D8)
  public static let tapbackSymbolFont = Font.system(size: 26, weight: .bold)
  public static let tapbackLetters = Font.system(size: 14, weight: .black, design: .rounded)
  public static let tapbackPunctuation = Font.system(size: 30, weight: .black, design: .rounded)
  public static let tapbackBadgeWidth: CGFloat = 42
  public static let tapbackBadgeHeight: CGFloat = 48
  public static let tapbackBadgeCircle: CGFloat = 34
  public static let tapbackBadgeScale: CGFloat = 0.72
  public static let messageSnapshotMaxHeight: CGFloat = 640
  public static let messageContextDim: Double = 0.55
  public static let messageContextTopInset: CGFloat = 72
  public static let messageContextBottomInset: CGFloat = 36
  public static let reactionPaletteHeight: CGFloat = 64
  public static let actionRowHeight: CGFloat = 52
  public static let actionMenuRadius: CGFloat = 24
  public static let actionMenuWidth: CGFloat = 240
  public static let photoStackHeight: CGFloat = 240
  public static let photoStackTilt: Double = 2.5
  public static let gallerySpacing: CGFloat = 4
  public static let contextBackgroundBlur: CGFloat = 4
  public static let reactionEmojiFont = Font.system(size: 28)
  public static let reactionSelectorHeight: CGFloat = 54
  public static let reactionSelectorGap: CGFloat = 10
  public static let reactionSelectorFace = Font.system(size: 23, weight: .medium)
  public static let reactionFont = Font.system(size: 24)
  public static let reactionBadgeFont = Font.system(size: 16)
  public static let reactionPickerWidth: CGFloat = 400
  public static let reactionPaletteControl: CGFloat = 44
  public static let reactionPaletteSpacing: CGFloat = 6
  // The main circle meets the bubble's top curve; the tiny dot sits beside its corner.
  public static let reactionOffset: CGFloat = -34
  public static let reactionHorizontalOffset: CGFloat = 8
  public static let reactionClearance: CGFloat = 42
  public static let contextPopScale: CGFloat = 0.88
  public static let contextActionScale: CGFloat = 0.96
  public static let contextSpringDuration: Double = 0.3
  public static let contextSpringBounce: Double = 0.16
  public static let contextFadeDuration: Double = 0.16
  public static let tapbackMoreCircle: CGFloat = 40
  public static let tapbackMoreTrail: CGFloat = 6
  public static let tapbackMoreDot: CGFloat = 3
  public static let followDistance: CGFloat = 100
  public static let typingDotSize: CGFloat = 8
  public static let photoDraftWidth: CGFloat = 96
  public static let photoDraftHeight: CGFloat = 76
  public static let photoDraftRadius: CGFloat = 12
  public static let photoRemoveSize: CGFloat = 22
  public static let photoWidth: CGFloat = 270
  public static let photoHeight: CGFloat = 340
  public static let photoPlaceholderHeight: CGFloat = 160
  public static let photoRadius: CGFloat = 20
  public static let headerBlurDistance: CGFloat = 24
  public static let headerBlurOpacity: Double = 0.9
  public static let background = Color.black
  public static let danger = Color(hex: 0xFF453A)
  public static let incoming = Color(hex: 0x262628)
  public static let outgoing = Color(hex: 0x007AFF)
  public static let secondary = Color(hex: 0x8E8E93)
  public static let separator = Color(hex: 0x303033)
  public static let foreground = Color.white
  public static let avatarTop = Color(hex: 0xFF7580)
  public static let avatarBottom = Color(hex: 0xE51E2A)
  public static let control = Color(hex: 0x252527)
  public static let body = Font.system(size: 17)
  public static let detailsTitle = Font.system(size: 28, weight: .bold)
  public static let headerName = Font.system(size: 15, weight: .semibold)
  public static let title = Font.system(size: 17, weight: .semibold)
  public static let preview = Font.system(size: 15)
  public static let caption = Font.system(size: 12)
  public static let pinLabel = Font.system(size: 12)
  public static let initial = Font.system(size: 48, weight: .regular, design: .serif)
  public static let avatarInitial = Font.system(size: 22, weight: .medium)
  public static let icon = Font.system(size: 21, weight: .regular)
  public static let pinControlSize: CGFloat = 32
  public static let pinControlIcon = Font.system(size: 15, weight: .semibold)
  public static let smallIcon = Font.system(size: 12, weight: .semibold)
  public static let horizontal: CGFloat = 20
  public static let previewWidth: CGFloat = 340
  public static let previewHeight: CGFloat = 480
  public static let pinnedAvatar: CGFloat = 82
  public static let detailsAvatar: CGFloat = 64
  public static let sendButton: CGFloat = 30
  public static let bubbleGutter: CGFloat = 70
  public static let rowAvatar: CGFloat = 45
  public static let headerAvatar: CGFloat = 44
  public static let controlHeight: CGFloat = 44
  public static let composerHeight: CGFloat = 46
  public static let rowHeight: CGFloat = 84
  public static let bubbleRadius: CGFloat = 25
  public static let bubbleInset: CGFloat = 14
  public static let bubbleSpacing: CGFloat = 8
  public static let groupSpacing: CGFloat = 28
  public static let pinGap: CGFloat = 18
  public static let pinRowGap: CGFloat = 18
  public static let bottomInset: CGFloat = 8
  public static let toolbarGap: CGFloat = 12
}

public struct MessagesGlass: ViewModifier {
  public func body(content: Content) -> some View {
    if #available(iOS 26.0, macOS 26.0, *) {
      content.glassEffect(.regular, in: Capsule())
    } else {
      content.background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 0.5))
    }
  }
}
/// Full-width translucent surface for content scrolling beneath navigation controls.
public struct MessagesHeaderBlur: ViewModifier {
  public let scrollOffset: CGFloat
  public func body(content: Content) -> some View {
    if #available(iOS 26.0, macOS 26.0, *) {
      content  // safeAreaBar owns the native progressive scroll-edge blur.
    } else {
      content.background {
        Rectangle().fill(.thinMaterial)
          .opacity(min(max(scrollOffset / MessagesStyle.headerBlurDistance, 0), 1))
          .ignoresSafeArea(edges: .top)
          .allowsHitTesting(false)
      }
    }
  }
}
/// Native scroll geometry keeps the header effect independent of lazy row layout.
public struct MessagesScrollTracking: ViewModifier {
  @Binding var offset: CGFloat
  public func body(content: Content) -> some View {
    if #available(iOS 26.0, macOS 26.0, *) {
      content
    } else {
      content.onScrollGeometryChange(for: CGFloat.self) { geometry in
        min(
          MessagesStyle.headerBlurDistance,
          max(0, geometry.contentOffset.y + geometry.contentInsets.top))
      } action: { _, newOffset in
        offset = newOffset
      }
    }
  }
}
extension View {
  @ViewBuilder public func messagesBar<Bar: View>(
    edge: VerticalEdge, @ViewBuilder content: () -> Bar
  ) -> some View {
    if #available(iOS 26.0, macOS 26.0, *) {
      self.safeAreaBar(edge: edge, spacing: 0, content: content)
    } else {
      self.safeAreaInset(edge: edge, spacing: 0, content: content)
    }
  }
  @ViewBuilder public func messagesScrollEdges() -> some View {
    if #available(iOS 26.0, macOS 26.0, *) {
      self.scrollEdgeEffectStyle(.soft, for: .all)
    } else {
      self
    }
  }

  public func messagesHeaderBlur(scrollOffset: CGFloat) -> some View {
    modifier(MessagesHeaderBlur(scrollOffset: scrollOffset))
  }
  public func messagesTrackScroll(offset: Binding<CGFloat>) -> some View {
    modifier(MessagesScrollTracking(offset: offset))
  }

  public func messagesGlass() -> some View { modifier(MessagesGlass()) }
}

public struct MessagesBubbleShape: Shape {
  public let outgoing: Bool
  public init(outgoing: Bool) { self.outgoing = outgoing }
  public func path(in rect: CGRect) -> Path {
    let inset: CGFloat = 6
    let radius = min(MessagesStyle.bubbleRadius, (rect.height - 3) / 2)
    let right = rect.width - inset
    let bottom = rect.height - 3
    var path = Path()
    path.move(to: CGPoint(x: inset + radius, y: 0))
    path.addLine(to: CGPoint(x: right - radius, y: 0))
    path.addQuadCurve(to: CGPoint(x: right, y: radius), control: CGPoint(x: right, y: 0))
    path.addLine(to: CGPoint(x: right, y: bottom - radius))
    path.addQuadCurve(
      to: CGPoint(x: right - radius, y: bottom), control: CGPoint(x: right, y: bottom))
    path.addLine(to: CGPoint(x: inset + radius, y: bottom))
    path.addCurve(
      to: CGPoint(x: 0, y: rect.height), control1: CGPoint(x: 18, y: bottom + 1),
      control2: CGPoint(x: 10, y: rect.height + 1))
    path.addQuadCurve(
      to: CGPoint(x: inset + 1, y: bottom - 10), control: CGPoint(x: 8, y: bottom - 1))
    path.addQuadCurve(
      to: CGPoint(x: inset, y: bottom - radius), control: CGPoint(x: inset, y: bottom - 16))
    path.addLine(to: CGPoint(x: inset, y: radius))
    path.addQuadCurve(to: CGPoint(x: inset + radius, y: 0), control: CGPoint(x: inset, y: 0))
    path.closeSubpath()
    if outgoing {
      path = path.applying(CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: rect.width, ty: 0))
    }
    return path
  }
}
