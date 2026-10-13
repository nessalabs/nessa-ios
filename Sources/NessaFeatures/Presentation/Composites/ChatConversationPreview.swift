import NessaDesignSystem
import SwiftUI

/// Read-only context-menu preview; opening it never starts an agent session.
struct ChatConversationPreview: View {
  @ObservedObject var store: MessagesViewModel
  let selection: ChatMenuSelection
  private let name: String
  private let title: String
  init(store: MessagesViewModel, selection: ChatMenuSelection) {
    self.store = store
    self.selection = selection
    name = store.agentName(for: selection.identifier)
    title = store.chatName(selection.identifier)
  }
  private var state: MessagesViewModel.PreviewState {
    selection.isCurrent(in: store) ? store.previewState(for: selection.identifier) : .unavailable
  }
  private var placeholder: String {
    switch state {
    case .available: return ""
    case .loading: return "Loading conversation…"
    case .empty: return "No messages yet"
    case .unavailable: return "Preview unavailable"
    }
  }
  var body: some View {
    VStack(spacing: NessaSpacing.md) {
      VStack(spacing: NessaSpacing.xs) {
        AgentAvatar(name: name, size: MessagesStyle.headerAvatar)
        Text(title).font(MessagesStyle.title)
      }.padding(.top, NessaSpacing.md)
      ScrollView {
        VStack(spacing: MessagesStyle.groupSpacing) {
          if case .available(let conversation) = state {
            ForEach(conversation.messages.suffix(3)) { turn in
              VStack(spacing: MessagesStyle.bubbleSpacing) {
                if !turn.userText.isEmpty { MessageBubble(text: turn.userText, outgoing: true) }
                ForEach(Array(turn.bubbles.enumerated()), id: \.offset) { _, text in
                  MessageBubble(text: text, outgoing: false)
                }
              }
            }
          } else {
            Text(placeholder)
              .font(MessagesStyle.caption).foregroundStyle(MessagesStyle.secondary)
              .padding(.vertical, NessaSpacing.xl)
          }
        }.padding(.horizontal, NessaSpacing.sm)
      }
      .defaultScrollAnchor(.bottom)
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
  }
}
