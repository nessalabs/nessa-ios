import NessaDesignSystem
import SwiftUI

/// A message this phone sent that its chat doesn't show yet: the sent bubble, with "Sending…"
/// under it while it goes, or "Couldn't send" and a way to try again if it didn't get through.
struct OutgoingMessageView: View {
  let message: OutgoingMessagesViewModel.Message
  let onRetry: () -> Void

  var body: some View {
    VStack(alignment: .trailing, spacing: NessaSpacing.xs) {
      if !message.attachments.isEmpty {
        Label(attachmentSummary, systemImage: "paperclip")
          .font(MessagesStyle.caption).foregroundStyle(MessagesStyle.secondary)
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
      if !message.text.isEmpty {
        MessageBubble(text: message.text, outgoing: true)
      }
      status.padding(.horizontal, MessagesStyle.bubbleInset)
    }
  }

  @ViewBuilder private var status: some View {
    switch message.state {
    case .sending:
      Text("Sending…").font(MessagesStyle.caption).foregroundStyle(MessagesStyle.secondary)
    case .failed(let reason):
      Button(action: onRetry) {
        VStack(alignment: .trailing, spacing: NessaSpacing.xxs) {
          Label("Couldn’t send. Tap to try again.", systemImage: "exclamationmark.circle")
            .foregroundStyle(MessagesStyle.danger)
          if let reason {
            Text(reason).foregroundStyle(MessagesStyle.secondary)
              .multilineTextAlignment(.trailing)
          }
        }
        .font(MessagesStyle.caption)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Couldn’t send. \(reason ?? "")")
      .accessibilityHint("Tries sending this message again")
    }
  }

  private var attachmentSummary: String {
    let count = message.attachments.count
    if message.attachments.allSatisfy(\.isImage) { return count == 1 ? "1 photo" : "\(count) photos" }
    return count == 1 ? "1 attachment" : "\(count) attachments"
  }
}
