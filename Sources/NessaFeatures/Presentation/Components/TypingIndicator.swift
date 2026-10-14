import NessaDesignSystem
import SwiftUI

struct TypingIndicator: View {
  var body: some View {
    HStack {
      // Lines up with the reply bubbles above it; the tail trails into the margin.
      MessagesTypingDots()
      Spacer()
    }.accessibilityElement(children: .ignore).accessibilityLabel("Agent is typing")
  }
}
