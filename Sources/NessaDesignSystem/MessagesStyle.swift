import SwiftUI

/// Measurements in points, taken from the 440-point-wide Messages references.
public enum MessagesStyle {
  public static let pinAction = Color(hex: 0xFF9F0A)
  /// Archiving is quiet and undoable: a neutral grey, never a hue.
  public static let archiveAction = Color(hex: 0x636366)
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
  public static let contextSpringDuration: Double = 0.25
  public static let contextSpringBounce: Double = 0.16
  public static let contextFadeDuration: Double = 0.15
  /// A message too near an edge for its menu first glides to where the menu has room; the
  /// palette and menu open only once it is there.
  public static let contextShiftAnimation = Animation.spring(duration: 0.2, bounce: 0)
  /// A move shorter than this happens with the menu's own spring rather than before it.
  public static let contextShiftThreshold: CGFloat = 2
  public static let tapbackMoreCircle: CGFloat = 40
  public static let tapbackMoreTrail: CGFloat = 6
  public static let tapbackMoreDot: CGFloat = 3
  public static let followDistance: CGFloat = 100
  /// How far from the bottom the thread's own follow may rest before it scrolls again.
  public static let pinTolerance: CGFloat = 1
  /// How long a follow scroll may take to come to rest, its spring's settle plus slack.
  public static let followSettleTime: TimeInterval = 1.2
  /// How long after a layout change a scroll coming to rest is still the system's.
  public static let layoutSettleWindow: TimeInterval = 0.6
  /// How long a newly opened thread spends settling before growth counts as new messages.
  public static let openSettleTime: TimeInterval = 1
  public static let typingDotSize: CGFloat = 8
  public static let typingDotSpacing: CGFloat = 5
  /// How bright a dot is between its turns.
  public static let typingDotRestOpacity: Double = 0.35
  /// One full pass of the three dots plus the rest after them.
  public static let typingCycle: TimeInterval = 1.3
  /// How far into the cycle (as a fraction) each dot starts after the one before it: 0.15 s.
  public static let typingStep: Double = 0.115
  /// How long (as a fraction of the cycle) one dot's glow lasts: 0.4 s, leaving a rest.
  public static let typingPulse: Double = 0.31
  /// How much a dot grows at the peak of its turn.
  public static let typingDotPeakScale: CGFloat = 1.15
  /// A reply that replaces a typing bubble arrives with its bubble already there, growing out
  /// of the typing bubble's frame on the list's own spring; only its text fades in.
  public static var replyMorphInsertion: AnyTransition {
    .asymmetric(
      insertion: .modifier(
        active: MessageContentReveal(shown: false), identity: MessageContentReveal(shown: true)),
      removal: bubbleRemoval)
  }
  /// The text of a growing reply fades in once its bubble is mostly open, so no line shows
  /// outside the fill while the fill is still small.
  public static let replyTextReveal = Animation.easeOut(duration: 0.12).delay(0.14)
  public static let typingBubbleHorizontalInset: CGFloat = 14
  public static let typingBubbleVerticalInset: CGFloat = 13
  public static let typingTailLarge: CGFloat = 12
  public static let typingTailSmall: CGFloat = 6
  public static let photoDraftWidth: CGFloat = 96
  public static let photoDraftHeight: CGFloat = 76
  public static let photoDraftRadius: CGFloat = 12
  public static let photoRemoveSize: CGFloat = 22
  public static let photoWidth: CGFloat = 270
  public static let photoHeight: CGFloat = 340
  public static let photoPlaceholderHeight: CGFloat = 160
  public static let photoRadius: CGFloat = 20
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
  /// How far the header's dither reaches down before it is gone.
  public static let ditherHeight: CGFloat = 150
  /// The bottom bar's ground reaches this far above the bar.
  public static let footerRise: CGFloat = 40
  public static let emptyAvatar: CGFloat = 56
  public static let rowSeparator = NessaColor.hairline
  /// The multi-select mark: a grey ring at rest, a white disc with a dark tick when chosen.
  public static let selectionMark: CGFloat = 22
  public static let selectionRingWidth: CGFloat = 1.5
  public static let selectionRingOpacity: Double = 0.28
  public static let selectionTick = Font.system(size: 11, weight: .bold)
  /// A chosen mark grows from this scale on `selectionPop`.
  public static let selectionPopScale: CGFloat = 0.6
  public static let selectionPop = Animation.spring(duration: 0.14, bounce: 0.2)
  /// A selected row is lifted this faintly off the ground.
  public static let selectedRowFill = NessaColor.foreground.opacity(0.05)
  public static let selectedRowRadius: CGFloat = 14
  /// A control swapping in place grows from this scale.
  public static let swapScale: CGFloat = 0.5
  /// A deleted or archived row fading out before the rows below close up: a
  /// micro-interaction.
  public static let rowFadeOut: Double = 0.12
  /// How long a reconnect runs before the inbox offers Try again.
  public static let reconnectPatience: Double = 5
  /// How long the list takes to close up after a row leaves, before the row's fade can be
  /// cleared for wherever it went (the archive, say).
  public static let rowSettle: Double = 0.35
  public static let sendPressScale: CGFloat = 0.86
  public static let headerPressScale: CGFloat = 0.97
  public static let emptyTitle = Font.system(size: 22, weight: .semibold)
  public static let unreadDot: CGFloat = 10
  /// The connection's live dot, beside its status word.
  public static let statusDot: CGFloat = 8
  /// A hairline between the rows of one card.
  public static let rowDivider: CGFloat = 0.5
  public static let body = Font.system(size: 17)
  /// An agent reply's markdown, kept as tight as the bubble's own text.
  public static let markdownBlockSpacing: CGFloat = 6
  public static let markdownListIndent: CGFloat = 16
  public static let markdownMarkerGap: CGFloat = 6
  public static let markdownQuoteBar: CGFloat = 3
  public static let markdownCodeRadius: CGFloat = 8
  public static let markdownCodeInset: CGFloat = 8
  public static let markdownCodeFill = NessaColor.foreground.opacity(0.06)
  public static let markdownRule: CGFloat = 0.5
  public static let markdownCode = Font.system(size: 14, design: .monospaced)
  /// A heading steps up modestly from the body: weight first, then a little size.
  public static func markdownHeading(_ level: Int) -> Font {
    switch level {
    case 1: return Font.system(size: 20, weight: .bold)
    case 2: return Font.system(size: 18, weight: .semibold)
    default: return Font.system(size: 17, weight: .semibold)
    }
  }
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
  /// A chat pinned or unpinned grows from, or shrinks to, this scale in the grid.
  public static let pinEnterScale: CGFloat = 0.6
  public static let detailsAvatar: CGFloat = 64
  public static let sendButton: CGFloat = 30
  public static let bubbleGutter: CGFloat = 70
  public static let rowAvatar: CGFloat = 45
  /// The agent's disc in the thread's navigation bar title.
  public static let titleAvatar: CGFloat = 28
  public static let controlHeight: CGFloat = 44
  public static let jumpToLatestSize: CGFloat = 36
  public static let jumpToLatestIcon = Font.system(size: 16, weight: .semibold)
  /// The same spring as the thread's own follow, so a jump and a follow move alike.
  public static let jumpToLatestAnimation = Animation.spring(duration: 0.25, bounce: 0)
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
  public static let sentEntranceDistance: CGFloat = 56
  public static let sentEntranceScale: CGFloat = 0.8
  /// A reply grows out of where the typing dots were, from its own tail corner.
  public static let replyEntranceDistance: CGFloat = 6
  public static let replyEntranceScale: CGFloat = 0.8
  /// One spring for the bubble and for the scroll that follows it, so the two move as one.
  /// Messages arrive many times a day, so it is short with only a hint of overshoot.
  public static let bubbleEntranceAnimation = Animation.spring(duration: 0.25, bounce: 0.15)
  /// The fade finishes early so the overshoot happens on a solid bubble.
  public static let bubbleFadeAnimation = Animation.easeOut(duration: 0.1)
  /// The list follows on the same timing without the overshoot, so the bubble bounces and
  /// the list doesn't.
  public static let messageFollowAnimation = Animation.spring(duration: 0.25, bounce: 0)
  public static var bubbleRemoval: AnyTransition { .opacity.combined(with: .scale(scale: 0.9)) }
  /// The typing bubble grows in like a reply and gets out of the way fast when the reply
  /// lands, so the reply reads as taking its place rather than crossing over it.
  public static var typingTransition: AnyTransition {
    .asymmetric(
      insertion: bubbleInsertion(outgoing: false),
      removal: AnyTransition.opacity.animation(.easeOut(duration: NessaMotion.normal / 2)))
  }
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
  /// The home screen's greeting: the one serif line in the app, set like a title page.
  public static let greeting = Font.system(size: 30, weight: .regular, design: .serif)
  /// The line under the greeting saying where a message will go.
  public static let greetingDetail = Font.system(size: 15)
  public static let greetingGap: CGFloat = 16
  /// The round buttons at the home screen's top corners.
  public static let homeButton: CGFloat = 44
  /// The sidebar's title and its section labels.
  public static let sidebarTitle = Font.system(size: 28, weight: .regular, design: .serif)
  /// The title's margin below the safe area.
  public static let sidebarTitleTop: CGFloat = NessaSpacing.lg
  /// The settings page's rows and the gap above each group of them.
  public static let settingsRowHeight: CGFloat = 52
  public static let settingsGroupGap: CGFloat = NessaSpacing.lg
  public static let sidebarSection = Font.system(size: 14)
  public static let sidebarRow = Font.system(size: 17)
  public static let sidebarRowHeight: CGFloat = 44
  public static let sidebarIcon: CGFloat = 22
  /// A screen's title set in its bar beside the back button, as Agents does.
  public static let barTitle = Font.system(size: 22, weight: .bold)
  /// The filter chips above a list.
  public static let chipHeight: CGFloat = 34
  public static let chipInset: CGFloat = 14
  /// The Agents list: room above each group's label, between a row's icon and text, around
  /// each row, and either side of a card; and the gap between a row's two lines.
  public static let agentsSectionGap: CGFloat = 30
  public static let agentsRowGap: CGFloat = 14
  public static let agentsRowInset: CGFloat = 13
  public static let agentsCardGutter: CGFloat = 16
  public static let rowLineGap: CGFloat = 2
  public static let rowIcon: CGFloat = 20
  /// A permission review's card: its corner, insets and spacing, the box holding the exact
  /// request (at most so many lines where the card only previews it), and its answers.
  public static let permissionCardRadius: CGFloat = 26
  public static let permissionCardInset: CGFloat = 18
  public static let permissionCardGap: CGFloat = 14
  public static let permissionRequestRadius: CGFloat = 12
  public static let permissionRequestFill = Color.white.opacity(0.06)
  public static let permissionRequestLineSpacing: CGFloat = 3
  public static let permissionRequestLines = 4
  public static let permissionButtonHeight: CGFloat = 46
  /// The New chat pill's plus.
  public static let newChatIcon: CGFloat = 18
  public static let newChatIconWeight: CGFloat = 1.8
  /// A channel's row in the sidebar: its name in serif beside a lettered tile lit in the
  /// home screen's halftone.
  public static let channelRowHeight: CGFloat = 56
  public static let channelName = Font.system(size: 21, weight: .regular, design: .serif)
  public static let channelTile: CGFloat = 38
  public static let channelTileRadius: CGFloat = 11
  /// The tile's light: the home screen's warm grey, as dots.
  public static let channelLight = HomeLightStyle.light.opacity(0.9)
  public static let channelInitial = Font.system(size: 19, weight: .regular, design: .serif)
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
      // Soft at both ends: content fades out under the header and composer instead of being
      // cut along a hard line.
      self.scrollEdgeEffectStyle(.soft, for: .top).scrollEdgeEffectStyle(.soft, for: .bottom)
    } else {
      self
    }
  }

  public func messagesGlass() -> some View { modifier(MessagesGlass()) }
  public func messagesComposerSurface() -> some View { modifier(MessagesComposerSurface()) }
}

/// Ties a typing bubble to the reply that replaces it, so the reply's bubble grows out of the
/// typing bubble's frame instead of the two crossing over.
public struct MessageMorph: Equatable, @unchecked Sendable {
  public let id: String
  public let namespace: Namespace.ID
  public init(id: String, namespace: Namespace.ID) {
    self.id = id
    self.namespace = namespace
  }
}

extension EnvironmentValues {
  @Entry public var messageMorph: MessageMorph? = nil
  @Entry public var messageContentShown: Bool = true
}

/// A message bubble's fill: the sent bubble in the lit accent, the received one a raised
/// card with a hairline so it holds its edge on the near-black ground.
///
/// Only the fill takes part in the reply morph. The text keeps its final layout and fades in, so
/// it never wraps inside the small typing frame while the bubble grows around it.
public struct MessageBubbleSurface: ViewModifier {
  let outgoing: Bool
  @Environment(\.messageMorph) private var morph
  @Environment(\.messageContentShown) private var shown
  public func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: MessagesStyle.bubbleRadius, style: .continuous)
    content
      .opacity(shown ? 1 : 0)
      .animation(MessagesStyle.replyTextReveal, value: shown)
      .background {
        Group {
          if outgoing {
            shape.fill(MessagesStyle.outgoingFill)
          } else {
            shape.fill(MessagesStyle.incoming)
              .overlay(shape.strokeBorder(MessagesStyle.incomingBorder, lineWidth: 0.5))
          }
        }
        .modifier(MorphFrame(morph: morph))
      }
  }
}

/// The insertion state of a reply growing out of a typing bubble: its text hidden, its fill
/// shown. A transition can only wrap the whole bubble, so it hands the state down.
public struct MessageContentReveal: ViewModifier {
  let shown: Bool
  public func body(content: Content) -> some View {
    content.environment(\.messageContentShown, shown)
  }
}

private struct MorphFrame: ViewModifier {
  let morph: MessageMorph?
  func body(content: Content) -> some View {
    if let morph {
      content.matchedGeometryEffect(
        id: morph.id, in: morph.namespace, properties: .frame, anchor: .bottomLeading)
    } else {
      content
    }
  }
}

extension View {
  public func messageBubbleSurface(outgoing: Bool) -> some View {
    modifier(MessageBubbleSurface(outgoing: outgoing))
  }
}

/// The screens' near-black ground.
public struct MessagesAmbientGround: ViewModifier {
  public func body(content: Content) -> some View {
    content.background { MessagesStyle.background.ignoresSafeArea() }
  }
}

/// A fine grain thinning down from the top edge behind a header. Drawn as part of the header
/// rather than the ground, so it sits above the scroll edge effect and stays one even texture.
public struct MessagesHeaderGrain: ViewModifier {
  public func body(content: Content) -> some View {
    content.background(alignment: .top) {
      NessaDither().frame(height: MessagesStyle.ditherHeight)
        .ignoresSafeArea(edges: .top)
    }
  }
}

/// The ground under the bottom bar: solid from the screen's edge to the middle of the composer,
/// so nothing scrolling beneath reads through or pokes out beside it, then fading upward while
/// a faint glyph grain thins out above the bar, mirroring the header's grain.
///
/// Applied to the scrolling content, not the bar: it then sits under the bar's glass and under
/// any control floated on the content (the jump arrow), instead of veiling them.
public struct MessagesFooterGrain: ViewModifier {
  let lit: Bool
  public func body(content: Content) -> some View {
    content.overlay {
      GeometryReader { geometry in
        // The bottom inset here is the bar plus the home indicator. The solid ground stops
        // half a composer below the bar's top: mid-composer for a one-line bar. A taller bar
        // (a multi-line draft, rows stacked above the composer) only covers more, never less.
        let below = geometry.safeAreaInsets.bottom
        let height = below + MessagesStyle.footerRise
        let solid = max(0, below - MessagesStyle.composerHeight / 2) / max(height, 1)
        ZStack {
          LinearGradient(
            stops: [
              .init(color: MessagesStyle.background, location: 0),
              .init(color: MessagesStyle.background, location: solid),
              .init(color: MessagesStyle.background.opacity(0), location: 1),
            ], startPoint: .bottom, endPoint: .top)
          NessaGlyphGrain(lit: lit)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .offset(y: below)
      }
      .allowsHitTesting(false)
    }
  }
}

/// The header grain for a screen under the system navigation bar: drawn on the content, from
/// the very top of the screen, so it sits under the bar's own controls.
public struct MessagesTopGrain: ViewModifier {
  public func body(content: Content) -> some View {
    content.overlay {
      GeometryReader { geometry in
        NessaDither().frame(height: MessagesStyle.ditherHeight)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
          .offset(y: -geometry.safeAreaInsets.top)
      }
      .allowsHitTesting(false)
    }
  }
}

extension View {
  public func messagesTopGrain() -> some View { modifier(MessagesTopGrain()) }
  public func messagesAmbientGround() -> some View { modifier(MessagesAmbientGround()) }
  public func messagesFooterGrain(lit: Bool = false) -> some View {
    modifier(MessagesFooterGrain(lit: lit))
  }
  public func messagesHeaderGrain() -> some View { modifier(MessagesHeaderGrain()) }
}
