import NessaDesignSystem
import SwiftUI

/// The gateway sheet, laid out like the agent details sheet: a title row with the close button
/// on its centre line, then one card and one full-width action, all on one spacing step.
struct NessaConnectionView: View {
  @ObservedObject var store: MessagesViewModel
  @Binding var address: String
  let instance: String
  @State private var draftAddress = ""
  @State private var credential = ""
  /// The sheet's height fitted to what it holds, so no empty half sheet hangs under the action.
  @State private var fittedHeight: CGFloat?
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: NessaSpacing.lg) {
        if store.connected {
          statusCard(connected: true)
          Button { Task { await store.manualDisconnect() } } label: {
            Text("Disconnect").foregroundStyle(MessagesStyle.danger)
              .frame(maxWidth: .infinity, minHeight: MessagesStyle.controlHeight)
              .background(MessagesStyle.control, in: Capsule())
          }
          .font(MessagesStyle.title).buttonStyle(.nessaPress)
        } else if store.hasSavedConnection {
          statusCard(connected: false)
          Button { Task { await store.reconnectSavedConnection() } } label: {
            Text(store.busy ? "Connecting…" : "Connect").frame(maxWidth: .infinity)
          }
          .buttonStyle(.nessaPrimary).disabled(store.busy || store.phoneSetupBusy)
          errorText
        } else {
          VStack(spacing: 0) {
            TextField("wss://your-host/session", text: $draftAddress).nessaCredentialInput()
              .modifier(ConnectionRow())
            divider
            SecureField("Credential", text: $credential).nessaCredentialInput()
              .modifier(ConnectionRow())
          }
          .font(MessagesStyle.body).nessaCard()
          Button {
            let selectedAddress = draftAddress
            let selectedCredential = credential
            Task {
              await store.connect(
                address: selectedAddress, credential: selectedCredential, instance: instance)
              if store.connected { address = selectedAddress }
            }
          } label: {
            Text(store.busy ? "Connecting…" : "Connect").frame(maxWidth: .infinity)
          }
          .buttonStyle(.nessaPrimary).disabled(store.busy || credential.isEmpty)
          errorText
        }
      }
      .padding(.horizontal, MessagesStyle.horizontal)
      // The title's line box leaves room under its glyphs, so this tops it up to the same gap
      // the card keeps from the action below it.
      .padding(.top, NessaSpacing.sm)
      .padding(.bottom, NessaSpacing.xl)
    }
    .scrollDismissesKeyboard(.interactively)
    .onScrollGeometryChange(for: CGFloat.self) { geometry in
      geometry.contentSize.height + geometry.contentInsets.top + geometry.contentInsets.bottom
    } action: { _, height in
      fittedHeight = height
    }
    .messagesScrollEdges()
    .messagesBar(edge: .top) { header.messagesHeaderGrain() }
    .foregroundStyle(MessagesStyle.foreground)
    .messagesAmbientGround()
    .onAppear { draftAddress = store.currentGatewayAddress ?? address }
    .presentationDetents(fittedHeight.map { [.height($0), .large] } ?? [.medium, .large])
    .presentationDragIndicator(.visible)
    .presentationBackground(MessagesStyle.background)
    .presentationCornerRadius(AgentDetailsStyle.cardRadius * 2)
  }

  /// The title and the close button share one row and one centre line, as in agent details.
  private var header: some View {
    HStack(spacing: NessaSpacing.sm) {
      Text("Connection").font(AgentDetailsStyle.title)
        .accessibilityAddTraits(.isHeader)
      Spacer(minLength: NessaSpacing.xs)
      Button { dismiss() } label: {
        Image(systemName: "xmark").font(MessagesStyle.icon)
          .frame(width: MessagesStyle.controlHeight, height: MessagesStyle.controlHeight)
          .messagesGlass()
      }
      .buttonStyle(.nessaPress)
      .accessibilityLabel("Close connection")
    }
    .frame(minHeight: MessagesStyle.controlHeight)
    .padding(.horizontal, MessagesStyle.horizontal)
    .padding(.top, NessaSpacing.sm)
  }

  private var endpoint: String {
    if store.connected { return store.currentGatewayAddress ?? address }
    return store.savedReconnectGatewayAddress ?? "Saved gateway unavailable"
  }

  /// The status and the gateway as two rows of one card, their labels on one leading edge.
  private func statusCard(connected: Bool) -> some View {
    VStack(spacing: 0) {
      HStack(spacing: NessaSpacing.xs) {
        Text("Status").foregroundStyle(MessagesStyle.secondary)
        Spacer(minLength: NessaSpacing.md)
        Circle().fill(connected ? NessaColor.accent : NessaColor.mutedForeground)
          .frame(width: MessagesStyle.statusDot, height: MessagesStyle.statusDot)
        Text(connected ? "Connected" : "Disconnected")
      }
      .modifier(ConnectionRow())
      .accessibilityElement(children: .combine)
      divider
      VStack(alignment: .leading, spacing: NessaSpacing.xxs) {
        Text("Gateway").font(MessagesStyle.caption).foregroundStyle(MessagesStyle.secondary)
        Text(endpoint).font(NessaType.mono).textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, NessaSpacing.sm)
      .padding(.horizontal, NessaSpacing.md)
    }
    .font(MessagesStyle.body).nessaCard()
  }

  private var divider: some View {
    Rectangle().fill(NessaColor.hairline).frame(height: MessagesStyle.rowDivider)
      .padding(.leading, NessaSpacing.md)
  }

  @ViewBuilder private var errorText: some View {
    if let error = store.error ?? store.phoneSyncError {
      Text(error).font(MessagesStyle.caption).foregroundStyle(MessagesStyle.secondary)
        .padding(.horizontal, NessaSpacing.md)
    }
  }
}

/// One row of a connection card: a control's height, the card's inner inset.
private struct ConnectionRow: ViewModifier {
  func body(content: Content) -> some View {
    content.padding(.horizontal, NessaSpacing.md)
      .frame(maxWidth: .infinity, minHeight: MessagesStyle.controlHeight, alignment: .leading)
  }
}
