import NessaDesignSystem
import SwiftUI

struct TypingIndicator: View {
  var body: some View {
    HStack {
      MessagesTypingDots().padding(MessagesStyle.bubbleInset)
        .background(
          MessagesStyle.incoming,
          in: RoundedRectangle(cornerRadius: MessagesStyle.bubbleRadius, style: .continuous))
      Spacer()
    }.accessibilityElement(children: .ignore).accessibilityLabel("Agent is typing")
  }
}
