import NessaDesignSystem
import SwiftUI

/// The inbox's controls in the system navigation bar, the same bar the thread uses, so going
/// in and out of a thread is one bar trading its items rather than two headers sliding past
/// each other.
struct InboxToolbar: ToolbarContent {
  let editing: Bool
  let onEdit: () -> Void
  let showingArchived: Bool
  let onToggleArchived: () -> Void
  /// While chats are being deleted, the bar's controls wait.
  let disabled: Bool
  var body: some ToolbarContent {
    // The inbox is pushed, so its leading corner is the back button; while selecting, Done
    // takes it. The account lives at the sidebar's foot.
    if editing {
      ToolbarItem(placement: .cancellationAction) {
        Button("Done", action: onEdit).font(MessagesStyle.body).disabled(disabled)
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
        Button("Select chats", systemImage: "checkmark.circle", action: onEdit)
        Button(
          showingArchived ? "Show messages" : "Archived chats", systemImage: "archivebox",
          action: onToggleArchived)
      } label: {
        Image(systemName: "line.3.horizontal.decrease")
      }.accessibilityLabel("Messages options").disabled(disabled)
    }
  }
}
