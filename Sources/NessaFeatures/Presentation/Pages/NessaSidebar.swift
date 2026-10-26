import NessaDesignSystem
import SwiftUI

/// The sidebar under the home screen: Agents, where every chat is, then a row for each
/// channel, with New chat always in reach at its foot.
struct NessaSidebar: View {
  @ObservedObject var store: MessagesViewModel
  let onAgents: () -> Void
  let onChannel: (NessaChannel) -> Void
  let onNewChat: () -> Void
  let onSettings: () -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        Text("Nessa").font(MessagesStyle.sidebarTitle).foregroundStyle(MessagesStyle.foreground)
          .padding(.horizontal, NessaSpacing.md).padding(.bottom, NessaSpacing.sm)
          .accessibilityAddTraits(.isHeader)
        row("Agents", icon: .agents, trailing: agentsHint, action: onAgents)
        if !store.channels.isEmpty {
          section("Channels")
          ForEach(store.channels) { channel in
            NessaChannelRow(name: channel.name, unread: hasUnread(channel)) {
              onChannel(channel)
            }
          }
        }
      }
      .padding(.horizontal, NessaSpacing.xs)
      .padding(.bottom, NessaSpacing.md)
    }
    .scrollIndicators(.hidden)
    .messagesScrollEdges()
    // Rows scrolled up fade out at the sidebar's top instead of running under the status bar.
    .mask {
      VStack(spacing: 0) {
        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
          .frame(height: NessaSpacing.md)
        Color.black
      }
    }
    .safeAreaInset(edge: .bottom, spacing: 0) { foot }
    .background(MessagesStyle.background.ignoresSafeArea())
  }

  private func hasUnread(_ channel: NessaChannel) -> Bool {
    store.conversations(inChannel: channel.id).contains { store.unreadChats.contains($0.id) }
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
    // The list fades out under the foot instead of running behind its buttons.
    .background {
      LinearGradient(
        stops: [
          .init(color: MessagesStyle.background, location: 0),
          .init(color: MessagesStyle.background, location: 0.6),
          .init(color: MessagesStyle.background.opacity(0), location: 1),
        ], startPoint: .bottom, endPoint: .top
      )
      .padding(.top, -MessagesStyle.footerRise)
      .ignoresSafeArea(edges: .bottom)
    }
  }

  private func section(_ title: String) -> some View {
    Text(title).font(MessagesStyle.sidebarSection).foregroundStyle(MessagesStyle.secondary)
      .padding(.horizontal, NessaSpacing.sm)
      .padding(.top, NessaSpacing.lg).padding(.bottom, NessaSpacing.xxs)
      .accessibilityAddTraits(.isHeader)
  }

  /// What the Agents row says beside its name: how many work right now, if any.
  private var agentsHint: String? {
    let working = store.agentsGlance.count(.working)
    return working > 0 ? "\(working) working" : nil
  }

  private func row(
    _ title: String, icon: NessaIconName, trailing: String? = nil,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) {
      HStack(spacing: NessaSpacing.sm) {
        NessaIcon(icon).frame(width: MessagesStyle.sidebarIcon)
        Text(title).lineLimit(1)
        Spacer(minLength: 0)
        if let trailing {
          Text(trailing).font(MessagesStyle.preview).foregroundStyle(MessagesStyle.secondary)
        }
      }
      .font(MessagesStyle.sidebarRow).foregroundStyle(MessagesStyle.foreground)
      .padding(.horizontal, NessaSpacing.sm)
      .frame(height: MessagesStyle.sidebarRowHeight)
      .contentShape(Rectangle())
    }
    .buttonStyle(.nessaPress)
  }
}
