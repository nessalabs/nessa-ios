import NessaDesignSystem
import SwiftUI

struct ConversationRow: View {
  let conversation: NessaConversation
  let agentName: String
  var body: some View {
    HStack(alignment: .center, spacing: NessaSpacing.sm) {
      AgentAvatar(name: agentName, size: MessagesStyle.rowAvatar)
      VStack(alignment: .leading, spacing: NessaSpacing.xxs) {
        HStack(spacing: NessaSpacing.xxs) {
          Text(conversation.title ?? agentName).font(MessagesStyle.title).lineLimit(1)
          Spacer(minLength: NessaSpacing.xxs)
          Text(timestamp).font(MessagesStyle.caption).foregroundStyle(MessagesStyle.secondary)
            .fixedSize()
          Image(systemName: "chevron.right").font(MessagesStyle.smallIcon).foregroundStyle(
            MessagesStyle.separator)
        }
        Text(
          conversation.running ? "Nessa is working…" : conversation.preview ?? "New conversation"
        )
        .font(MessagesStyle.preview).nessaShimmer(active: conversation.running)
        .contentTransition(.opacity)
        .lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
      }.frame(minHeight: MessagesStyle.rowHeight, alignment: .leading)
        .overlay(alignment: .bottom) {
          Rectangle().fill(MessagesStyle.rowSeparator).frame(height: 0.5)
        }
    }.foregroundStyle(MessagesStyle.foreground)
  }
  private var timestamp: String {
    let date = Date(timeIntervalSince1970: conversation.updatedAtMs / 1000)
    if Calendar.current.isDateInToday(date) {
      return date.formatted(date: .omitted, time: .shortened)
    }
    if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
    return date.formatted(.dateTime.month(.abbreviated).day())
  }
}
