import NessaDesignSystem
import SwiftUI

/// The first thing a new inbox shows: Nessa's disc in its wash, and a way to begin.
struct InboxEmptyState: View {
  let onCompose: () -> Void
  var body: some View {
    VStack(spacing: NessaSpacing.md) {
      ZStack {
        NessaWash(feathered: true)
          .frame(width: MessagesStyle.emptyWashSize, height: MessagesStyle.emptyWashSize)
        NessaAvatarDisc(seed: "Nessa", size: MessagesStyle.emptyAvatar)
      }
      .frame(height: MessagesStyle.emptyWashVisibleHeight)
      Text("Your chats, one message away.").font(MessagesStyle.emptyTitle)
        .multilineTextAlignment(.center)
      Button(action: onCompose) {
        Label("New message", systemImage: "square.and.pencil").font(MessagesStyle.title)
          .padding(.horizontal, NessaSpacing.lg)
          .frame(height: MessagesStyle.controlHeight)
          .background(MessagesStyle.outgoingFill, in: Capsule())
      }.buttonStyle(.nessaPress)
    }
    .foregroundStyle(MessagesStyle.foreground)
    .frame(maxWidth: .infinity)
    .padding(.vertical, NessaSpacing.xl)
    .nessaEntrance()
  }
}
