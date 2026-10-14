import NessaDesignSystem
import SwiftUI

/// One frozen menu selection; updating the source row cannot retarget an open menu.
struct ChatMenuSelection {
  let identifier: String
  let conversationID: String?
  let scope: Int
  @MainActor init(identifier: String, store: MessagesViewModel) {
    self.identifier = identifier
    conversationID = store.existingConversationID(for: identifier)
    scope = store.deliveryScopeRevision
  }
  @MainActor func isCurrent(in store: MessagesViewModel) -> Bool {
    scope == store.deliveryScopeRevision && !store.isDeleting(identifier)
      && store.existingConversationID(for: identifier) == conversationID
  }
}
struct ChatMenuAction: Identifiable {
  let id: String
  let title: String
  let symbol: String
  let destructive: Bool
  let enabled: Bool
  let perform: @MainActor () -> Void
}

@MainActor func chatMenuActions(
  selection: ChatMenuSelection, store: MessagesViewModel, layoutAnimation: Animation? = nil,
  onDelete: @escaping (String) -> Void
) -> [ChatMenuAction] {
  let id = selection.identifier
  func action(
    _ key: String, _ title: String, _ symbol: String, enabled: Bool = true,
    destructive: Bool = false, perform: @escaping @MainActor () -> Void
  ) -> ChatMenuAction {
    .init(
      id: key, title: title, symbol: symbol, destructive: destructive, enabled: enabled,
      perform: { if selection.isCurrent(in: store) { perform() } })
  }
  let archived = selection.conversationID.map { store.archivedChats.contains($0) } == true
  return [
    action(
      "pin", store.isPinned(id) ? "Unpin" : "Pin", store.isPinned(id) ? "pin.slash" : "pin",
      enabled: store.canTogglePin(id)
    ) { withAnimation(layoutAnimation) { store.togglePin(id) } },
    action("unread", "Mark as Unread", "bubble") { store.markUnread(id) },
    action(
      "alerts", store.mutedChats.contains(id) ? "Show Alerts" : "Hide Alerts",
      store.mutedChats.contains(id) ? "bell" : "bell.slash"
    ) { store.toggleAlerts(id) },
    action(
      "archive", archived ? "Unarchive" : "Archive", "archivebox",
      enabled: selection.conversationID != nil
    ) {
      if let conversation = selection.conversationID {
        withAnimation(layoutAnimation) { store.setArchived(!archived, conversationID: conversation) }
      }
    },
    action(
      "delete", "Delete", "trash", enabled: store.connected && selection.conversationID != nil,
      destructive: true
    ) {
      if store.connected, let conversation = selection.conversationID { onDelete(conversation) }
    },
  ]
}
