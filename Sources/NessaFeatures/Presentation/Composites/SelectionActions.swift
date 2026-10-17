import NessaDesignSystem
import SwiftUI

/// The bottom bar while chats are selected: Archive (or Unarchive) and Delete side by side,
/// in the composer's glass. Each asks first, in the system's alert.
struct SelectionActions: View {
  /// The list on screen is the archive, so Archive takes chats back out of it.
  let showingArchived: Bool
  let archiveEnabled: Bool
  let deleteEnabled: Bool
  let onArchive: () -> Void
  let onDelete: () -> Void
  var body: some View {
    HStack(spacing: MessagesStyle.toolbarGap) {
      action(
        showingArchived ? "Unarchive" : "Archive", symbol: "archivebox",
        tint: MessagesStyle.foreground, perform: onArchive
      ).disabled(!archiveEnabled)
      action("Delete", symbol: "trash", tint: MessagesStyle.danger, perform: onDelete)
        .disabled(!deleteEnabled)
    }
  }
  private func action(
    _ title: String, symbol: String, tint: Color, perform: @escaping () -> Void
  ) -> some View {
    Button(action: perform) {
      Label(title, systemImage: symbol).font(MessagesStyle.body).foregroundStyle(tint)
        .frame(maxWidth: .infinity, minHeight: MessagesStyle.composerHeight)
        .messagesGlass()
    }.buttonStyle(.nessaPress)
  }
}
