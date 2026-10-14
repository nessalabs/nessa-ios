import SwiftUI

/// Measurements in points, taken from the 440-point-wide Messages references.
public enum MessagesStyle {
  public static let confirmationHeight: CGFloat = 300
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
  /// How long after a layout change a scroll coming to rest is still the system's.
  public static let layoutSettleWindow: TimeInterval = 0.6
  public static let typingDotSize: CGFloat = 8
  public static let typingWaveAmplitude: CGFloat = 3.5
  public static let typingWavePeriod: TimeInterval = 1.3
  public static let typingWavePhase: Double = .pi / 2
  public static let typingDotMinimumOpacity: Double = 0.55
  public static let typingDotMinimumScale: CGFloat = 0.88
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
  public static let background = NessaColor.background
  public static let danger = NessaColor.destructive
  public static let incoming = NessaColor.card
  public static let incomingBorder = NessaColor.hairline
  public static let outgoing = NessaColor.accent
  /// The sent bubble lit from above: the accent settling into a deeper step at its foot.
  public static let outgoingFill = LinearGradient(
    colors: [NessaColor.accent, NessaColor.accentDeep], startPoint: .top, endPoint: .bottom)
  public static let link = NessaColor.accentInk
  public static let secondary = NessaColor.mutedForeground
  public static let separator = NessaColor.muted
  public static let foreground = NessaColor.foreground
  public static let control = NessaColor.muted
  /// How far the brand wash reaches down behind the inbox's header before it is gone.
  public static let washHeight: CGFloat = 240
  public static let washIntensity: Double = 0.32
  public static let emptyWashSize: CGFloat = 220
  public static let emptyAvatar: CGFloat = 96
  public static let emptyWashVisibleHeight: CGFloat = 165
  public static let rowSeparator = NessaColor.hairline
  /// A control swapping in place grows from this scale.
  public static let swapScale: CGFloat = 0.5
  public static let sendPressScale: CGFloat = 0.86
  public static let headerPressScale: CGFloat = 0.97
  public static let emptyTitle = Font.system(size: 22, weight: .semibold)
  public static let unreadDot: CGFloat = 10
  public static let body = Font.system(size: 17)
  public static let detailsTitle = Font.system(size: 28, weight: .bold)
  public static let headerName = Font.system(size: 15, weight: .semibold)
  public static let title = Font.system(size: 17, weight: .semibold)
  public static let preview = Font.system(size: 15)
  public static let caption = Font.system(size: 12)
  public static let pinLabel = Font.system(size: 12)
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
  public static let jumpToLatestSize: CGFloat = 36
  public static let jumpToLatestIcon = Font.system(size: 16, weight: .semibold)
  public static let jumpToLatestAnimation = NessaMotion.emphasized(0.36)
  public static let composerHeight: CGFloat = 46
  public static let composerRadius: CGFloat = 23
  public static let replyBackgroundBlur: CGFloat = 14
  public static let replyPreviewOpacity: Double = 0.55
  public static let replyPreviewRadius: CGFloat = 18
  public static let replyConnectorWidth: CGFloat = 44
  public static let replyConnectorHeight: CGFloat = 28
  public static let replyConnectorStroke: CGFloat = 2
  public static let rowHeight: CGFloat = 84
  public static let bubbleRadius: CGFloat = 25
  public static let bubbleInset: CGFloat = 12
  public static let bubbleHorizontalInset: CGFloat = 16
  public static let bubbleSpacing: CGFloat = 8
  /// A sent bubble rises out of the composer: it starts this far below its place, small and
  /// tucked into its tail corner, and springs up with a little overshoot.
  public static let sentEntranceDistance: CGFloat = 28
  public static let sentEntranceScale: CGFloat = 0.7
  /// A reply grows out of where the typing dots were, from its own tail corner.
  public static let replyEntranceDistance: CGFloat = 6
  public static let replyEntranceScale: CGFloat = 0.8
  /// One spring for the bubble and for the scroll that follows it, so the two move as one:
  /// quick off the mark, a visible but short overshoot, settled in under half a second.
  public static let bubbleEntranceAnimation = Animation.spring(duration: 0.45, bounce: 0.3)
  /// The fade finishes early so the overshoot happens on a solid bubble.
  public static let bubbleFadeAnimation = Animation.easeOut(duration: 0.14)
  public static let messageFollowAnimation = bubbleEntranceAnimation
  public static let bubbleRemoval = AnyTransition.opacity.combined(with: .scale(scale: 0.9))
  public static func bubbleInsertion(outgoing: Bool) -> AnyTransition {
    let anchor: UnitPoint = outgoing ? .bottomTrailing : .bottomLeading
    let insertion: AnyTransition = AnyTransition.opacity.animation(bubbleFadeAnimation)
      .combined(
        with: .offset(y: outgoing ? sentEntranceDistance : replyEntranceDistance))
      .combined(
        with: .scale(scale: outgoing ? sentEntranceScale : replyEntranceScale, anchor: anchor))
    return .asymmetric(insertion: insertion, removal: bubbleRemoval)
  }
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

public struct MessagesComposerSurface: ViewModifier {
  public func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: MessagesStyle.composerRadius, style: .continuous)
    if #available(iOS 26.0, macOS 26.0, *) {
      content.glassEffect(.regular, in: shape)
    } else {
      content.background(.ultraThinMaterial, in: shape)
        .overlay(shape.stroke(.white.opacity(0.12), lineWidth: 0.5))
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
      // Hard at the top so text never reads through behind the header's glass.
      self.scrollEdgeEffectStyle(.hard, for: .top).scrollEdgeEffectStyle(.soft, for: .bottom)
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
  public func messagesComposerSurface() -> some View { modifier(MessagesComposerSurface()) }
}

/// A message bubble's fill: the sent bubble in the lit accent, the received one a raised
/// card with a hairline so it holds its edge on the near-black ground.
public struct MessageBubbleSurface: ViewModifier {
  let outgoing: Bool
  public func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: MessagesStyle.bubbleRadius, style: .continuous)
    if outgoing {
      content.background(MessagesStyle.outgoingFill, in: shape)
    } else {
      content.background(MessagesStyle.incoming, in: shape)
        .overlay(shape.strokeBorder(MessagesStyle.incomingBorder, lineWidth: 0.5))
    }
  }
}

extension View {
  public func messageBubbleSurface(outgoing: Bool) -> some View {
    modifier(MessageBubbleSurface(outgoing: outgoing))
  }
}

/// The near-black ground with the brand wash glowing faintly down from the top edge,
/// mostly behind the header so it never sits under running text.
public struct MessagesAmbientGround: ViewModifier {
  public func body(content: Content) -> some View {
    content.background {
      MessagesStyle.background
        .overlay(alignment: .top) {
          // Faded out by a mask rather than cut by the canvas edge, so it ends nowhere.
          NessaWash(intensity: MessagesStyle.washIntensity)
            .frame(height: MessagesStyle.washHeight)
            .mask(
              LinearGradient(
                stops: [.init(color: .black, location: 0), .init(color: .clear, location: 1)],
                startPoint: .top, endPoint: .bottom))
            .offset(y: -MessagesStyle.washHeight * 0.3)
        }
        .ignoresSafeArea()
    }
  }
}

extension View {
  public func messagesAmbientGround() -> some View { modifier(MessagesAmbientGround()) }
}
