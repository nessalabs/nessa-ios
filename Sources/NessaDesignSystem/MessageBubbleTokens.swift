import SwiftUI

/// Message styles shared by the SwiftPM design library and the Exact transcript.
public enum MessagesStyle {
  public static let background = NessaColor.background
  public static let foreground = NessaColor.foreground
  public static let secondary = NessaColor.mutedForeground
  public static let control = NessaColor.muted
  public static let incoming = NessaColor.card
  public static let incomingBorder = NessaColor.hairline
  public static let outgoing = NessaColor.accent
  /// The sent bubble lit from above: the accent settling into a deeper step at its foot.
  public static let outgoingFillColors = [outgoing, NessaColor.accentDeep]

  public static let bubbleInset: CGFloat = 12
  public static let bubbleHorizontalInset: CGFloat = 16
  public static let bubbleRadius: CGFloat = 25
  public static let bubbleBorderWidth: CGFloat = 0.5
  public static let bubbleGutter: CGFloat = 70

  public static let replyPreviewOpacity: Double = 0.55
  public static let replyPreviewRadius: CGFloat = 18
  public static let replyConnectorWidth: CGFloat = 44
  public static let replyConnectorHeight: CGFloat = 28
  public static let replyConnectorStroke: CGFloat = 2

  public static let photoWidth: CGFloat = 270
  public static let photoRadius: CGFloat = 20
  public static let photoStackHeight: CGFloat = 240
  public static let photoStackTilt: Double = 2.5
  public static let gallerySpacing: CGFloat = 4

  public static let tapbackBackground = Color(hex: 0x18A4ED)
  public static let tapbackBadgeCircle: CGFloat = 34
  // The main circle meets the bubble's top curve; the tiny dot sits beside its corner.
  public static let reactionOffset: CGFloat = -34
  public static let reactionClearance: CGFloat = 42

  public static let typingBubbleHorizontalInset: CGFloat = 14
  public static let typingBubbleVerticalInset: CGFloat = 13
  public static let typingTailLarge: CGFloat = 12
  public static let typingTailSmall: CGFloat = 6
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
}
