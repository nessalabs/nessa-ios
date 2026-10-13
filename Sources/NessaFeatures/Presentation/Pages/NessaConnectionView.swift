import NessaDesignSystem
import SwiftUI

struct NessaConnectionView: View {
  @ObservedObject var store: MessagesViewModel
  @Binding var address: String
  let instance: String
  @State private var draftAddress = ""
  @State private var credential = ""
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      Form {
        if store.connected {
          connectionStatus("Connected")
          Section {
            Button("Disconnect") { Task { await store.manualDisconnect() } }
              .font(MessagesStyle.title)
              .frame(maxWidth: .infinity, minHeight: MessagesStyle.controlHeight)
              .messagesGlass().buttonStyle(.plain)
          }.listRowBackground(Color.clear).listRowInsets(EdgeInsets())
        } else if store.hasSavedConnection {
          connectionStatus("Disconnected")
          Section {
            Button(store.busy ? "Connecting…" : "Connect") {
              Task { await store.reconnectSavedConnection() }
            }.disabled(store.busy || store.phoneSetupBusy)
              .font(MessagesStyle.title)
              .frame(maxWidth: .infinity, minHeight: MessagesStyle.controlHeight)
              .messagesGlass().buttonStyle(.plain)
          }.listRowBackground(Color.clear).listRowInsets(EdgeInsets())
          if let error = store.error ?? store.phoneSyncError {
            Section { Text(error).font(MessagesStyle.caption) }
          }
        } else {
          Section {
            TextField("wss://your-host/session", text: $draftAddress).nessaCredentialInput()
            SecureField("Credential", text: $credential).nessaCredentialInput()
            Button(store.busy ? "Connecting…" : "Connect") {
              let selectedAddress = draftAddress
              let selectedCredential = credential
              Task {
                await store.connect(
                  address: selectedAddress, credential: selectedCredential, instance: instance)
                if store.connected { address = selectedAddress }
              }
            }.disabled(store.busy || credential.isEmpty)
            if let error = store.error ?? store.phoneSyncError {
              Text(error).font(MessagesStyle.caption)
            }
          }
        }
      }.scrollDismissesKeyboard(.interactively).navigationTitle("Connection")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        .onAppear { draftAddress = store.currentGatewayAddress ?? address }
    }
  }
  private var endpoint: String {
    if store.connected { return store.currentGatewayAddress ?? address }
    return store.savedReconnectGatewayAddress ?? "Saved gateway unavailable"
  }
  private func connectionStatus(_ status: String) -> some View {
    Section {
      LabeledContent("Status", value: status)
      VStack(alignment: .leading, spacing: NessaSpacing.xxs) {
        Text("Gateway").font(MessagesStyle.caption).foregroundStyle(MessagesStyle.secondary)
        Text(endpoint).font(NessaType.mono).textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
  }

}
