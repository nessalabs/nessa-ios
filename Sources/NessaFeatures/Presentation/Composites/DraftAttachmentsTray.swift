import NessaDesignSystem
import SwiftUI

struct DraftAttachmentsTray: View {
  @Binding var attachments: [DraftAttachment]
  let sending: Bool
  var body: some View {
    ScrollView(.horizontal) {
      HStack(spacing: NessaSpacing.sm) {
        ForEach(attachments) { attachment in
          if attachment.isImage {
            PhotoAttachment(id: attachment.id.uuidString, draft: true) { attachment.data }
              .overlay(alignment: .topTrailing) {
                removeButton(attachment)
                  .padding(NessaSpacing.xs)
              }
          } else {
            HStack(spacing: NessaSpacing.xs) {
              Image(systemName: "doc")
              Text(attachment.name).lineLimit(1)
              removeButton(attachment)
            }.font(MessagesStyle.caption).padding(NessaSpacing.sm).messagesGlass()
          }
        }
      }
    }.scrollIndicators(.hidden).padding(.horizontal, MessagesStyle.horizontal)
  }
  private func removeButton(_ attachment: DraftAttachment) -> some View {
    Button {
      attachments.removeAll { $0.id == attachment.id }
    } label: {
      Image(systemName: "xmark").font(MessagesStyle.smallIcon)
        .foregroundStyle(MessagesStyle.foreground)
        .frame(width: MessagesStyle.photoRemoveSize, height: MessagesStyle.photoRemoveSize)
        .background(MessagesStyle.background.opacity(0.7), in: Circle())
        .frame(
          width: MessagesStyle.controlHeight, height: MessagesStyle.controlHeight,
          alignment: .topTrailing
        )
        .contentShape(Rectangle())
    }.buttonStyle(.plain).disabled(sending).accessibilityLabel("Remove \(attachment.name)")
  }
}
