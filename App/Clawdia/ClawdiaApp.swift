import SwiftUI
import UIKit
import ClawdiaFeatures

@main
struct ClawdiaApp: App {
    private let store: DevModeStore
    private let runtimeMode: ClawdiaRuntimeMode

    init() {
        let runtimeMode = ClawdiaRuntimeModeResolver.resolve()
        self.runtimeMode = runtimeMode
        self.store = Self.makeStore(runtimeMode: runtimeMode)
    }

    var body: some Scene {
        WindowGroup {
            ClawdiaRootView(
                store: store,
                runtimeMode: runtimeMode
            )
        }
    }

    private static func makeStore(runtimeMode: ClawdiaRuntimeMode) -> DevModeStore {
        let credentialStore = KeychainNostrAgentBridgeCredentialStore()
        let onboardingStore = UserDefaultsOnboardingConfigurationStore()
        let baseState: MockAppState = runtimeMode.allowsDevelopmentSurfaces ? .preview : .production
        guard let credentials = try? credentialStore.loadCredentials(),
              let configuration = try? credentials.bridgeConfiguration(),
              let sender = try? NostrPublishingAgentMessageSender(phonePrivateKeyHex: credentials.phonePrivateKeyHex),
              let receiver = try? NostrEncryptedAgentMessageReceiver(
                phonePrivateKeyHex: credentials.phonePrivateKeyHex,
                expectedSenderPublicKeyHex: credentials.desktopPublicKeyHex
              ) else {
            return DevModeStore(
                state: baseState,
                onboardingStore: onboardingStore,
                nostrCredentialStore: credentialStore,
                nostrRelaySubscriber: NostrWebSocketRelaySubscriber(),
                chatMessageRepository: CoreDataCloudKitChatMessageRepository.productionRepository(),
                phoneClientDisplayName: UIDevice.current.name
            )
        }

        return DevModeStore(
            state: baseState,
            onboardingStore: onboardingStore,
            nostrConfiguration: configuration,
            nostrMessageSender: sender,
            nostrMessageReceiver: receiver,
            nostrCredentialStore: credentialStore,
            nostrRelaySubscriber: NostrWebSocketRelaySubscriber(),
            chatMessageRepository: CoreDataCloudKitChatMessageRepository.productionRepository(),
            phoneClientDisplayName: UIDevice.current.name,
            initialDesktopPairingStatus: .paired(displayName: credentials.desktopDisplayName)
        )
    }
}
