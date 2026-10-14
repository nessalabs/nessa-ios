import NessaDesignSystem
import SwiftUI

/// The first thing a new inbox shows: Nessa's disc and a way to begin.
struct InboxEmptyState: View {
  let onCompose: () -> Void
  var body: some View {
    VStack(spacing: NessaSpacing.md) {
      NessaAvatarDisc(seed: "Nessa", size: MessagesStyle.emptyAvatar)
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
