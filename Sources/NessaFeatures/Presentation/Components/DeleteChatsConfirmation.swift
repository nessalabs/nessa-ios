import NessaDesignSystem
import SwiftUI

struct DeleteChatsConfirmation: View {
  let count: Int
  let onCancel: () -> Void
  let onDelete: () -> Void
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    VStack(spacing: NessaSpacing.md) {
      Text(count == 1 ? "Delete this chat?" : "Delete \(count) chats?")
        .font(MessagesStyle.title)
      Text("This permanently removes the selected conversations and their history from Nessa.")
        .font(MessagesStyle.body).foregroundStyle(MessagesStyle.secondary)
        .multilineTextAlignment(.center)
      Button(role: .destructive, action: onDelete) {
        Label(count == 1 ? "Delete chat" : "Delete \(count) chats", systemImage: "trash")
          .frame(maxWidth: .infinity, minHeight: MessagesStyle.controlHeight)
      }.buttonStyle(.borderedProminent).tint(MessagesStyle.danger)
      Button(action: onCancel) {
        Text("Cancel").frame(maxWidth: .infinity, minHeight: MessagesStyle.controlHeight)
      }.buttonStyle(.bordered).tint(MessagesStyle.foreground)
    }.font(MessagesStyle.body).foregroundStyle(MessagesStyle.foreground)
      .padding(NessaSpacing.lg).frame(maxWidth: .infinity)
      .presentationDetents(
        typeSize.isAccessibilitySize ? [.large] : [.height(MessagesStyle.confirmationHeight)]
      )
      .presentationDragIndicator(.visible)
      .presentationBackground(MessagesStyle.control)
  }
}
