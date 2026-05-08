import SwiftUI
import ClawdiaFeatures

@main
struct ClawdiaApp: App {
    private let store = Self.makeStore()

    var body: some Scene {
        WindowGroup {
            DevModeRootView(store: store)
        }
    }

    private static func makeStore() -> DevModeStore {
        let credentialStore = KeychainNostrAgentBridgeCredentialStore()
        guard let credentials = try? credentialStore.loadCredentials(),
              let configuration = try? credentials.bridgeConfiguration(),
              let sender = try? NostrPublishingAgentMessageSender(phonePrivateKeyHex: credentials.phonePrivateKeyHex) else {
            return DevModeStore()
        }

        return DevModeStore(
            nostrConfiguration: configuration,
            nostrMessageSender: sender
        )
    }
}
