import NessaDesignSystem
import SwiftUI

/// The chats the linked Mac shares with this phone, read-only. The list is
/// read again from the Mac each time it opens; what was read stays in this
/// pairing's private native cache, which the Mac's revoke withdraws.
struct LinkedDesktopChatsView: View {
  @ObservedObject var store: DesktopLinkViewModel
  var body: some View {
    List {
      if let error = store.chatsError {
        Text(error).font(MessagesStyle.caption).foregroundStyle(MessagesStyle.secondary)
          .listRowBackground(Color.clear)
      }
      if store.chats.isEmpty, !store.chatsLoading, store.chatsError == nil {
        Text("No chats shared yet. On your Mac, share a chat with this phone from its Share menu.")
          .font(MessagesStyle.body).foregroundStyle(MessagesStyle.secondary)
          .listRowBackground(Color.clear)
      }
      ForEach(store.chats) { conversation in
        NavigationLink(value: LinkedChatRoute(conversationID: conversation.id)) {
          ConversationRow(conversation: conversation, agentName: "Nessa")
        }
        .listRowBackground(Color.clear)
      }
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .background(MessagesStyle.background)
    .navigationTitle(store.linked?.name ?? "Your Mac")
    .refreshable { await store.refreshChats() }
    .task { await store.refreshChats() }
    .foregroundStyle(MessagesStyle.foreground)
  }
}

/// A shared chat opened from the linked Mac's list.
struct LinkedChatRoute: Hashable {
  let conversationID: String
}

/// One shared chat, read-only: the person's messages and Nessa's replies.
struct LinkedDesktopThreadView: View {
  @ObservedObject var store: DesktopLinkViewModel
  let conversationID: String
  @State private var view: NessaConversationView?
  @State private var failed = false
  var body: some View {
    ScrollView {
      LazyVStack(spacing: NessaSpacing.xs) {
        if let view {
          ForEach(view.messages) { turn in
            if !turn.userText.isEmpty {
              MessageBubble(text: turn.userText, outgoing: true)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            ForEach(turn.displayBubbles) { fragment in
              MessageBubble(text: fragment.text, outgoing: false)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
        } else if failed {
          Text("This chat couldn't be read from your Mac.")
            .font(MessagesStyle.caption).foregroundStyle(MessagesStyle.secondary)
        }
      }
      .padding(.horizontal, MessagesStyle.horizontal)
      .padding(.vertical, NessaSpacing.md)
    }
    .defaultScrollAnchor(.bottom)
    .background(MessagesStyle.background)
    .foregroundStyle(MessagesStyle.foreground)
    .navigationTitle(
      store.chats.first(where: { $0.id == conversationID })?.title ?? "Chat")
    .task {
      do {
        view = try await store.transcript(conversationID)
      } catch {
        failed = true
      }
    }
  }
}
