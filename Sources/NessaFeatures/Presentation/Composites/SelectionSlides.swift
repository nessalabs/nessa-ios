import NessaDesignSystem
import SwiftUI

/// The bottom bar while chats are selected: a slide to archive (or unarchive) them above a
/// slide to delete them. Each is its own deliberate confirm, so several chats never go with
/// one tap and no sheet is needed.
struct SelectionSlides: View {
  let count: Int
  /// The list on screen is the archive, so the first slide takes chats back out of it.
  let showingArchived: Bool
  let archiveEnabled: Bool
  let deleteEnabled: Bool
  let onArchive: () -> Void
  let onDelete: () -> Void
  var body: some View {
    VStack(spacing: MessagesStyle.selectionSlideGap) {
      NessaSlideToConfirm(
        "Slide to \(showingArchived ? "unarchive" : "archive") \(count)", symbol: "archivebox",
        tint: MessagesStyle.archiveAction, height: MessagesStyle.selectionBarHeight,
        onConfirm: onArchive
      ).disabled(!archiveEnabled)
      NessaSlideToConfirm(
        "Slide to delete \(count)", tint: MessagesStyle.danger,
        height: MessagesStyle.selectionBarHeight, onConfirm: onDelete
      ).disabled(!deleteEnabled)
    }
  }
}
