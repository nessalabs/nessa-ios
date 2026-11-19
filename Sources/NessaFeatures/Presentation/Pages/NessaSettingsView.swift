import NessaDesignSystem
import SwiftUI

/// The person's settings, opened from their disc at the sidebar's foot: one card per group,
/// each row leading to a page of its own: the connection, and the chats archived from Agents.
struct NessaSettingsView: View {
  @ObservedObject var store: MessagesViewModel
  @ObservedObject var desktop: DesktopLinkViewModel
  let onConnection: () -> Void
  let onArchived: () -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: MessagesStyle.settingsGroupGap) {
        VStack(spacing: 0) {
          row("Connection", action: onConnection) {
            Circle().fill(store.connected ? NessaColor.accent : NessaColor.mutedForeground)
              .frame(width: MessagesStyle.statusDot, height: MessagesStyle.statusDot)
            Text(status).foregroundStyle(MessagesStyle.secondary).lineLimit(1)
          }
        }
        .font(MessagesStyle.body).nessaCard()
        VStack(spacing: 0) {
          row("Archived chats", action: onArchived) { EmptyView() }
        }
        .font(MessagesStyle.body).nessaCard()
      }
      .padding(.horizontal, MessagesStyle.horizontal)
      .padding(.top, NessaSpacing.xs)
      .padding(.bottom, NessaSpacing.xl)
    }
    .messagesScrollEdges()
    .foregroundStyle(MessagesStyle.foreground)
    .messagesAmbientGround()
    .navigationTitle("Settings")
    .nessaInlineNavigationTitle()
    .toolbar { BarTitle("Settings") }
  }

  private func row<Detail: View>(
    _ title: String, action: @escaping () -> Void, @ViewBuilder detail: () -> Detail
  ) -> some View {
    Button(action: action) {
      HStack(spacing: NessaSpacing.xs) {
        Text(title)
        Spacer(minLength: NessaSpacing.md)
        detail()
        Image(systemName: "chevron.right").font(MessagesStyle.smallIcon)
          .foregroundStyle(MessagesStyle.separator)
      }
      .padding(.horizontal, NessaSpacing.md)
      .frame(maxWidth: .infinity, minHeight: MessagesStyle.settingsRowHeight)
      .contentShape(Rectangle())
    }
    .buttonStyle(.nessaPress)
    .accessibilityElement(children: .combine)
  }

  /// How the phone reaches its agents right now: the paired Mac by name when that is the way.
  private var status: String {
    if store.connected {
      guard let linked = desktop.linked, store.linkedDesktopID == linked.id else {
        return "Connected"
      }
      return linked.name
    }
    if store.reconnecting { return "Reconnecting…" }
    return "Not connected"
  }
}
