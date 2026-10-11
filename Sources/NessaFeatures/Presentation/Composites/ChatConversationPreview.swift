import NessaDesignSystem
import SwiftUI

/// Read-only context-menu preview; opening it never starts an agent session.
struct ChatConversationPreview: View {
  @ObservedObject var store: MessagesViewModel
  let agent: String
  var body: some View {
    VStack(spacing: NessaSpacing.md) {
      VStack(spacing: NessaSpacing.xs) {
        AgentAvatar(name: store.agentName(for: agent), size: MessagesStyle.headerAvatar)
        Text(store.chatName(agent)).font(MessagesStyle.title)
      }.padding(.top, NessaSpacing.md)
      ScrollView {
        VStack(spacing: MessagesStyle.groupSpacing) {
          if let conversation = store.agentPreviews[agent], !conversation.messages.isEmpty {
            ForEach(conversation.messages.suffix(3)) { turn in
              VStack(spacing: MessagesStyle.bubbleSpacing) {
                if !turn.userText.isEmpty { MessageBubble(text: turn.userText, outgoing: true) }
                ForEach(Array(turn.bubbles.enumerated()), id: \.offset) { _, text in
                  MessageBubble(text: text, outgoing: false)
                }
              }
            }
          } else {
            Text(store.hasConversation(agent) ? "Loading conversation…" : "No messages yet")
              .font(MessagesStyle.caption).foregroundStyle(MessagesStyle.secondary)
              .padding(.vertical, NessaSpacing.xl)
          }
        }.padding(.horizontal, NessaSpacing.sm)
      }
      HStack {
        Image(systemName: "plus").font(MessagesStyle.icon)
        Text("Message").font(MessagesStyle.body).foregroundStyle(MessagesStyle.secondary)
        Spacer()
        Image(systemName: "waveform").foregroundStyle(MessagesStyle.secondary)
      }.padding(NessaSpacing.md).messagesGlass().padding(NessaSpacing.sm)
    }
    .frame(width: MessagesStyle.previewWidth, height: MessagesStyle.previewHeight)
    .background(MessagesStyle.background)
    .foregroundStyle(MessagesStyle.foreground)
    .environment(\.colorScheme, .dark)
    .task { await store.loadPreview(agent) }
  }
}
