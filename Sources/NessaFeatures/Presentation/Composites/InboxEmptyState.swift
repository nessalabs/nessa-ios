import NessaDesignSystem
import SwiftUI

/// The first thing a new inbox shows: Nessa's disc in its dither, and a way to begin.
struct InboxEmptyState: View {
  let onCompose: () -> Void
  var body: some View {
    VStack(spacing: NessaSpacing.md) {
      ZStack {
        NessaDither(.radial, strength: NessaDither.defaultStrength * 1.5)
          .frame(width: MessagesStyle.emptyDitherSize, height: MessagesStyle.emptyDitherSize)
        NessaAvatarDisc(seed: "Nessa", size: MessagesStyle.emptyAvatar)
      }
      .frame(height: MessagesStyle.emptyDitherVisibleHeight)
      Text("Your chats, one message away.").font(MessagesStyle.emptyTitle)
        .multilineTextAlignment(.center)
      Button(action: onCompose) {
        Label("New message", systemImage: "square.and.pencil")
      }.buttonStyle(.nessaPrimary)
    }
    .foregroundStyle(MessagesStyle.foreground)
    .frame(maxWidth: .infinity)
    .padding(.vertical, NessaSpacing.xl)
    .nessaEntrance()
  }
}
