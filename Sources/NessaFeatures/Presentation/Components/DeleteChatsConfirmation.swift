import NessaDesignSystem
import SwiftUI

struct DeleteChatsConfirmation: View {
  /// Held from the moment the sheet opens: the caller clears its pending set as soon as the
  /// delete is confirmed, and the closing sheet must not re-read that as zero chats.
  @State private var count: Int
  let onCancel: () -> Void
  let onDelete: () -> Void
  @Environment(\.dynamicTypeSize) private var typeSize

  init(count: Int, onCancel: @escaping () -> Void, onDelete: @escaping () -> Void) {
    _count = State(initialValue: count)
    self.onCancel = onCancel
    self.onDelete = onDelete
  }

  var body: some View {
    VStack(spacing: NessaSpacing.md) {
      Text(count == 1 ? "Delete this chat?" : "Delete \(count) chats?")
        .font(MessagesStyle.title)
      Text("This permanently removes the selected conversations and their history from Nessa.")
        .font(MessagesStyle.body).foregroundStyle(MessagesStyle.secondary)
        .multilineTextAlignment(.center)
      // A slide rather than a button, so deleting is deliberate and can't happen by a stray tap.
      NessaSlideToConfirm(
        count == 1 ? "Slide to delete" : "Slide to delete \(count)", tint: MessagesStyle.danger,
        onConfirm: onDelete)
      Button(action: onCancel) {
        Text("Cancel").foregroundStyle(MessagesStyle.secondary)
          .frame(maxWidth: .infinity, minHeight: MessagesStyle.controlHeight)
          .contentShape(Rectangle())
      }.buttonStyle(.nessaPress)
    }.font(MessagesStyle.body).foregroundStyle(MessagesStyle.foreground)
      .padding(NessaSpacing.lg).frame(maxWidth: .infinity)
      .presentationDetents(
        typeSize.isAccessibilitySize ? [.large] : [.height(MessagesStyle.confirmationHeight)]
      )
      .presentationDragIndicator(.visible)
      .presentationBackground(MessagesStyle.control)
  }
}
