import NessaDesignSystem
import SwiftUI

struct InboxHeader: View {
  let editing: Bool
  /// Seeds the reader's own disc, so it stays the same face for one gateway.
  let accountSeed: String
  let onEdit: () -> Void
  let onSettings: () -> Void
  let showingArchived: Bool
  let onToggleArchived: () -> Void
  var body: some View {
    HStack {
      // The reader's own disc holds the account's actions; selecting chats lives there too,
      // and while selecting, Done takes its place.
      if editing {
        Button("Done", action: onEdit).font(MessagesStyle.body)
          .padding(.horizontal, NessaSpacing.md).frame(height: MessagesStyle.controlHeight)
          .messagesGlass().buttonStyle(.nessaPress)
      } else {
        Menu {
          Button("Select chats", systemImage: "checkmark.circle", action: onEdit)
          Button("Connection settings", systemImage: "network", action: onSettings)
        } label: {
          NessaAvatarDisc(seed: accountSeed, size: MessagesStyle.headerAvatar)
        }.accessibilityLabel("Account")
      }
      Spacer()
      Menu {
        Button(
          showingArchived ? "Show messages" : "Archived chats", systemImage: "archivebox",
          action: onToggleArchived)
      } label: {
        Image(systemName: "line.3.horizontal.decrease").font(MessagesStyle.icon)
          .frame(width: MessagesStyle.controlHeight, height: MessagesStyle.controlHeight)
          .messagesGlass()
      }.accessibilityLabel("Messages options")
    }
    // Centred on the screen, not between two buttons of different widths.
    .overlay {
      Text(showingArchived ? "Archived" : "Messages").font(MessagesStyle.title)
        .lineLimit(1).minimumScaleFactor(0.8)
        // Clear of the wider of the two buttons at large text sizes.
        .padding(.horizontal, NessaSpacing.xl * 2)
        .contentTransition(.opacity)
        .animation(NessaMotion.standard(), value: showingArchived)
    }
    .padding(.horizontal, MessagesStyle.horizontal).padding(.vertical, NessaSpacing.xxs)
  }
}
