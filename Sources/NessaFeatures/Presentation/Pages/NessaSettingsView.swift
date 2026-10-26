import NessaDesignSystem
import SwiftUI

/// The person's settings, opened from their disc at the sidebar's foot: one card per group,
/// each row leading to a page of its own. Connection is the first group; more join it here.
struct NessaSettingsView: View {
  @ObservedObject var store: MessagesViewModel
  @ObservedObject var desktop: DesktopLinkViewModel
  let onConnection: () -> Void

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: MessagesStyle.settingsGroupGap) {
        VStack(spacing: 0) {
          Button(action: onConnection) {
            HStack(spacing: NessaSpacing.xs) {
              Text("Connection")
              Spacer(minLength: NessaSpacing.md)
              Circle().fill(store.connected ? NessaColor.accent : NessaColor.mutedForeground)
                .frame(width: MessagesStyle.statusDot, height: MessagesStyle.statusDot)
              Text(status).foregroundStyle(MessagesStyle.secondary).lineLimit(1)
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

  /// How the phone reaches its agents right now: the paired Mac by name when that is the way.
  private var status: String {
    if store.connected { return desktop.linked?.name ?? "Connected" }
    if store.reconnecting { return "Reconnecting…" }
    return "Not connected"
  }
}
