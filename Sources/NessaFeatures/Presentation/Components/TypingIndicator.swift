import NessaDesignSystem
import SwiftUI

struct TypingIndicator: View {
  var body: some View {
    HStack {
      MessagesTypingDots().padding(.leading, MessagesStyle.typingTailSmall)
      Spacer()
    }.accessibilityElement(children: .ignore).accessibilityLabel("Agent is typing")
  }
}
