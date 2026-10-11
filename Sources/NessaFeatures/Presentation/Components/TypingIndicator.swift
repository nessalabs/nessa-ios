import NessaDesignSystem
import SwiftUI

struct TypingIndicator: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  private var dot: some View {
    Circle().fill(MessagesStyle.secondary)
      .frame(width: MessagesStyle.typingDotSize, height: MessagesStyle.typingDotSize)
  }
  var body: some View {
    HStack {
      HStack(spacing: NessaSpacing.xs) {
        ForEach(0..<3) { index in
          if reduceMotion {
            dot
          } else {
            dot.phaseAnimator([0, 1, 2]) { content, phase in
              content.opacity(phase == index ? 1 : 0.4).scaleEffect(phase == index ? 1 : 0.8)
            } animation: { _ in
              .easeInOut(duration: 0.35)
            }
          }
        }
      }.padding(MessagesStyle.bubbleInset)
        .background(MessagesStyle.incoming, in: MessagesBubbleShape(outgoing: false))
      Spacer()
    }.accessibilityElement(children: .ignore).accessibilityLabel("Agent is typing")
  }
}
