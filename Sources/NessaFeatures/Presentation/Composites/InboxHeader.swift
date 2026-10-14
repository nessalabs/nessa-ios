import NessaDesignSystem
import SwiftUI

struct InboxHeader: View {
  let editing: Bool
  let onEdit: () -> Void
  let onSettings: () -> Void
  let showingArchived: Bool
  let onToggleArchived: () -> Void
  var body: some View {
    HStack {
      Button(editing ? "Done" : "Edit", action: onEdit).font(MessagesStyle.body)
        .padding(.horizontal, NessaSpacing.md).frame(height: MessagesStyle.controlHeight)
        .messagesGlass().buttonStyle(.nessaPress)
      Spacer()
      Text(showingArchived ? "Archived" : "Messages").font(MessagesStyle.title)
        .contentTransition(.opacity)
        .animation(NessaMotion.standard(), value: showingArchived)
      Spacer()
      Menu {
        Button(
          showingArchived ? "Show messages" : "Archived chats", systemImage: "archivebox",
          action: onToggleArchived)
        Button("Connection settings", systemImage: "network", action: onSettings)
      } label: {
        Image(systemName: "line.3.horizontal.decrease").font(MessagesStyle.icon)
          .frame(width: MessagesStyle.controlHeight, height: MessagesStyle.controlHeight)
          .messagesGlass()
      }.accessibilityLabel("Messages options")
    }.padding(.horizontal, MessagesStyle.horizontal).padding(.vertical, NessaSpacing.xxs)
  }
}
