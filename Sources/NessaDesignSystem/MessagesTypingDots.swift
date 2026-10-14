import Foundation
import SwiftUI

/// The familiar chat typing bubble: three grey dots that light up one after another, then rest,
/// in a received bubble with its small trailing tail. The dots don't move; only their
/// brightness travels left to right, which is what people read as "typing".
public struct MessagesTypingDots: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @State private var startedAt = Date()

  public init() {}

  public var body: some View {
    Group {
      if reduceMotion {
        dots(at: nil)
      } else {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: scenePhase != .active)) {
          context in
          dots(at: context.date)
        }
      }
    }
    .padding(.horizontal, MessagesStyle.typingBubbleHorizontalInset)
    .padding(.vertical, MessagesStyle.typingBubbleVerticalInset)
    .messageBubbleSurface(outgoing: false)
    .background(alignment: .bottomLeading) { tail }
    .accessibilityHidden(true)
  }

  /// Two small circles trailing off the bubble's lower corner, as in every chat app. They stay
  /// inside the thread's side margin, since the bubble lines up with the replies above it.
  private var tail: some View {
    ZStack(alignment: .bottomLeading) {
      Circle().fill(MessagesStyle.incoming)
        .overlay(Circle().strokeBorder(MessagesStyle.incomingBorder, lineWidth: 0.5))
        .frame(width: MessagesStyle.typingTailLarge, height: MessagesStyle.typingTailLarge)
        .offset(x: -MessagesStyle.typingTailLarge / 4, y: MessagesStyle.typingTailLarge / 4)
      Circle().fill(MessagesStyle.incoming)
        .overlay(Circle().strokeBorder(MessagesStyle.incomingBorder, lineWidth: 0.5))
        .frame(width: MessagesStyle.typingTailSmall, height: MessagesStyle.typingTailSmall)
        .offset(
          x: -MessagesStyle.typingTailLarge * 2 / 3, y: MessagesStyle.typingTailLarge * 3 / 4)
    }
  }

  private func dots(at date: Date?) -> some View {
    HStack(spacing: MessagesStyle.typingDotSpacing) {
      ForEach(0..<3, id: \.self) { index in
        let glow = glow(index: index, at: date)
        Circle().fill(MessagesStyle.secondary)
          .frame(width: MessagesStyle.typingDotSize, height: MessagesStyle.typingDotSize)
          .scaleEffect(1 + (MessagesStyle.typingDotPeakScale - 1) * glow)
          .opacity(
            MessagesStyle.typingDotRestOpacity + (1 - MessagesStyle.typingDotRestOpacity) * glow)
      }
    }
  }

  /// 0 at rest, 1 at the peak of this dot's turn. Each dot's turn starts a step after the one
  /// before it; after the last, all three rest until the cycle repeats.
  private func glow(index: Int, at date: Date?) -> Double {
    guard let date else { return 0 }
    let cycle = date.timeIntervalSince(startedAt) / MessagesStyle.typingCycle
    let local = cycle - floor(cycle) - Double(index) * MessagesStyle.typingStep
    guard local >= 0, local < MessagesStyle.typingPulse else { return 0 }
    return sin(.pi * local / MessagesStyle.typingPulse)
  }
}
