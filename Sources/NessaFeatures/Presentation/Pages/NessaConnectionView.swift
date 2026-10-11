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
        Section {
          TextField("wss://your-host/session", text: $draftAddress).nessaCredentialInput()
          SecureField("Product credential", text: $credential).nessaCredentialInput()
        } header: {
          Text("Nessa gateway")
        } footer: {
          Text(
            "Use the gateway’s /session endpoint and a credential authorized for your conversations. On iPhone, use your Mac’s reachable address rather than localhost. Credentials stay in this device’s Keychain."
          )
        }
        Section {
          Button(store.busy ? "Connecting…" : "Connect") {
            let submittedAddress = draftAddress
            let submittedCredential = credential
            Task {
              await store.connect(
                address: submittedAddress, credential: submittedCredential, instance: instance)
              if store.connected {
                address = submittedAddress
                dismiss()
              }
            }
          }.disabled(store.busy || credential.isEmpty)
          if let error = store.error { Text(error).font(MessagesStyle.caption) }
        }
      }.navigationTitle("Connect to Nessa")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        .onAppear {
          draftAddress = address
          credential = store.savedCredential()
        }
    }
  }
}
