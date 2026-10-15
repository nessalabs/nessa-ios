import NessaDesignSystem
import SwiftUI

/// The inbox's controls in the system navigation bar, the same bar the thread uses, so going
/// in and out of a thread is one bar trading its items rather than two headers sliding past
/// each other.
struct InboxToolbar: ToolbarContent {
  let editing: Bool
  /// Select mode opened for one chat's Delete, so leaving it backs out: Cancel, not Done.
  let cancelsDelete: Bool
  /// Seeds the reader's own disc, so it stays the same face for one gateway.
  let accountSeed: String
  let onEdit: () -> Void
  let onSettings: () -> Void
  let showingArchived: Bool
  let onToggleArchived: () -> Void
  /// While chats are being deleted, the bar's controls wait.
  let disabled: Bool
  var body: some ToolbarContent {
    // The reader's own disc holds the account's actions; selecting chats lives there too,
    // and while selecting, Done takes its place.
    ToolbarItem(placement: .cancellationAction) {
      if editing {
        Button(cancelsDelete ? "Cancel" : "Done", action: onEdit).font(MessagesStyle.body)
          .disabled(disabled)
      } else {
        Menu {
          Button("Select chats", systemImage: "checkmark.circle", action: onEdit)
          Button("Connection settings", systemImage: "network", action: onSettings)
        } label: {
          NessaAvatarDisc(seed: accountSeed, size: MessagesStyle.accountAvatar)
        }.accessibilityLabel("Account").disabled(disabled)
      }
    }
    ToolbarItem(placement: .principal) {
      Text(showingArchived ? "Archived" : "Messages").font(MessagesStyle.title)
        .lineLimit(1).minimumScaleFactor(0.8)
        .contentTransition(.opacity)
        .animation(NessaMotion.standard(), value: showingArchived)
    }
    ToolbarItem(placement: .primaryAction) {
      Menu {
        Button(
          showingArchived ? "Show messages" : "Archived chats", systemImage: "archivebox",
          action: onToggleArchived)
      } label: {
        Image(systemName: "line.3.horizontal.decrease")
      }.accessibilityLabel("Messages options").disabled(disabled)
    }
  }
}
