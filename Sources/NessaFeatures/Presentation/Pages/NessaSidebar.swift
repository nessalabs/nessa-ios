import NessaDesignSystem
import SwiftUI

/// The sidebar under the home screen: every chat, pinned ones first, then the most recent,
/// with New chat always in reach at its foot.
struct NessaSidebar: View {
  @ObservedObject var store: MessagesViewModel
  /// The chat on screen, marked in the list.
  let current: String?
  let onAllChats: () -> Void
  let onChannel: (NessaChannel) -> Void
  let onOpen: (String) -> Void
  let onNewChat: () -> Void
  let onSettings: () -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        Text("Nessa").font(MessagesStyle.sidebarTitle).foregroundStyle(MessagesStyle.foreground)
          .padding(.horizontal, NessaSpacing.md).padding(.bottom, NessaSpacing.sm)
          .accessibilityAddTraits(.isHeader)
        row("Chats", icon: .chats, action: onAllChats)
        if !store.channels.isEmpty {
          section("Channels")
          ForEach(store.channels) { channel in
            row(channel.name, icon: .hash) { onChannel(channel) }
          }
        }
        if !pinned.isEmpty {
          section("Pinned")
          ForEach(pinned, id: \.self) { chatRow($0) }
        }
        if !recents.isEmpty {
          section("Recents")
          ForEach(recents) { chatRow($0.id) }
        }
      }
      .padding(.horizontal, NessaSpacing.xs)
      .padding(.bottom, MessagesStyle.homeButton + NessaSpacing.xl)
    }
    .scrollIndicators(.hidden)
    .messagesScrollEdges()
    .safeAreaInset(edge: .bottom, spacing: 0) { foot }
    .background(MessagesStyle.background.ignoresSafeArea())
  }

  private var foot: some View {
    HStack {
      Button(action: onSettings) {
        NessaAvatarDisc(seed: store.currentGatewayAddress ?? "nessa", size: MessagesStyle.homeButton)
      }
      .buttonStyle(.nessaPress)
      .accessibilityLabel("Connection settings")
      Spacer()
      Button(action: onNewChat) {
        HStack(spacing: NessaSpacing.xs) {
          NessaIcon(.plus, size: 18, weight: 1.8)
          Text("New chat")
        }
          .font(MessagesStyle.sidebarRow.weight(.medium))
          .padding(.horizontal, NessaSpacing.lg)
          .frame(height: MessagesStyle.homeButton)
          .foregroundStyle(MessagesStyle.background)
          .background(MessagesStyle.foreground, in: Capsule())
      }
      .buttonStyle(.nessaPress)
      .disabled(
        !store.connected || !store.conversationAuthorityReady || store.busy
          || store.pendingLoadError != nil || !store.pendingCreations.isEmpty)
    }
    .padding(.horizontal, NessaSpacing.md)
    .padding(.bottom, NessaSpacing.xs)
  }

  private var pinned: [String] {
    store.pinnedChats.filter { !store.isDeleting($0) && !store.archivedChats.contains($0) }
  }

  private var recents: [NessaConversation] {
    store.visibleConversations.filter {
      !store.isPinned($0.id) && !store.archivedChats.contains($0.id)
    }
  }

  private func section(_ title: String) -> some View {
    Text(title).font(MessagesStyle.sidebarSection).foregroundStyle(MessagesStyle.secondary)
      .padding(.horizontal, NessaSpacing.sm)
      .padding(.top, NessaSpacing.lg).padding(.bottom, NessaSpacing.xxs)
      .accessibilityAddTraits(.isHeader)
  }

  private func row(_ title: String, icon: NessaIconName, action: @escaping () -> Void)
    -> some View
  {
    Button(action: action) {
      HStack(spacing: NessaSpacing.sm) {
        NessaIcon(icon).frame(width: MessagesStyle.sidebarIcon)
        Text(title).lineLimit(1)
        Spacer(minLength: 0)
      }
      .font(MessagesStyle.sidebarRow).foregroundStyle(MessagesStyle.foreground)
      .padding(.horizontal, NessaSpacing.sm)
      .frame(height: MessagesStyle.sidebarRowHeight)
      .contentShape(Rectangle())
    }
    .buttonStyle(.nessaPress)
  }

  private func chatRow(_ id: String) -> some View {
    let unread = store.unreadChats.contains(id)
    return Button { onOpen(id) } label: {
      HStack(spacing: NessaSpacing.sm) {
        Group {
          if unread {
            Circle().fill(NessaColor.accent).frame(
              width: MessagesStyle.statusDot, height: MessagesStyle.statusDot)
          } else {
            NessaIcon(.chats, size: MessagesStyle.sidebarIcon - 2)
              .foregroundStyle(MessagesStyle.secondary)
          }
        }
        .frame(width: MessagesStyle.sidebarIcon)
        Text(store.chatName(id)).lineLimit(1).truncationMode(.tail)
          .fontWeight(unread ? .semibold : .regular)
        Spacer(minLength: 0)
      }
      .font(MessagesStyle.sidebarRow).foregroundStyle(MessagesStyle.foreground)
      .padding(.horizontal, NessaSpacing.sm)
      .frame(height: MessagesStyle.sidebarRowHeight)
      .background {
        if id == current {
          RoundedRectangle(cornerRadius: MessagesStyle.selectedRowRadius, style: .continuous)
            .fill(MessagesStyle.selectedRowFill)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.nessaPress)
    .accessibilityLabel(unread ? "\(store.chatName(id)), unread" : store.chatName(id))
    .accessibilityAddTraits(id == current ? .isSelected : [])
  }
}
