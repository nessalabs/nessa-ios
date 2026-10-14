import Foundation
import SwiftUI

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
    .frame(height: MessagesStyle.typingDotSize + MessagesStyle.typingWaveAmplitude * 2)
    .accessibilityHidden(true)
  }

  private func dots(at date: Date?) -> some View {
    HStack(spacing: NessaSpacing.xs) {
      ForEach(0..<3) { index in
        let wave =
          date.map {
            sin(
              $0.timeIntervalSince(startedAt) * 2 * .pi / MessagesStyle.typingWavePeriod
                - Double(index) * MessagesStyle.typingWavePhase)
          } ?? 0
        let lift = (wave + 1) / 2
        Circle().fill(NessaColor.thinking[index % NessaColor.thinking.count])
          .frame(width: MessagesStyle.typingDotSize, height: MessagesStyle.typingDotSize)
          .scaleEffect(
            date == nil
              ? 1
              : MessagesStyle.typingDotMinimumScale
                + CGFloat(lift) * (1 - MessagesStyle.typingDotMinimumScale)
          )
          .opacity(
            date == nil
              ? 1
              : MessagesStyle.typingDotMinimumOpacity
                + lift * (1 - MessagesStyle.typingDotMinimumOpacity)
          )
          .offset(y: -CGFloat(wave) * MessagesStyle.typingWaveAmplitude)
      }
    }
  }
}
