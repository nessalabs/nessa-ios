import NessaDesignSystem
import SwiftUI

/// The agent in the middle of the thread's navigation bar: its disc and name, opening the
/// details sheet. The bar itself, its back button and its edge swipe are the system's own.
struct ThreadTitle: View {
  let name: String
  let working: Bool
  let onDetails: () -> Void
  var body: some View {
    Button(action: onDetails) {
      HStack(spacing: NessaSpacing.xs) {
        AgentAvatar(name: name, size: MessagesStyle.titleAvatar, working: working)
        Text(name).font(MessagesStyle.headerName).lineLimit(1)
        Image(systemName: "chevron.right").font(MessagesStyle.smallIcon)
          .foregroundStyle(MessagesStyle.secondary)
      }
      .foregroundStyle(MessagesStyle.foreground)
    }
    .buttonStyle(NessaPressStyle(scale: MessagesStyle.headerPressScale))
    .accessibilityLabel("\(name) agent details")
  }
}
