import NessaDesignSystem
import SwiftUI

struct TypingIndicator: View {
  var body: some View {
    HStack {
      MessagesTypingDots().padding(.horizontal, MessagesStyle.bubbleHorizontalInset)
        .padding(.vertical, MessagesStyle.bubbleInset)
        .messageBubbleSurface(outgoing: false)
      Spacer()
    }.accessibilityElement(children: .ignore).accessibilityLabel("Agent is typing")
  }
}
