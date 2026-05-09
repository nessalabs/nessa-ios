import SwiftUI
import ClawdiaObservability

public final class DevModeStore: ObservableObject {
    @Published public private(set) var state: MockAppState
    @Published public private(set) var onboardingConfiguration: OnboardingConfiguration
    @Published public private(set) var desktopPairingStatus: DesktopPairingStatus = .notPaired
    private let telemetry: TelemetryClient
    private let onboardingStore: OnboardingConfigurationStoring
    private let nostrCredentialStore: NostrAgentBridgeCredentialStoring?
    private let nostrEntropy: any NostrEntropySource
    private let nostrRelayPublisher: any NostrRelayPublishing
    private let nostrRelaySubscriber: (any NostrRelaySubscribing)?
    private let nostrPlaintextEventSigner: NostrPlaintextRelayEventSigner
    private let chatMessageRepository: any ChatMessagePersisting
    private let chatMessageRetentionPolicy: ChatMessageRetentionPolicy
    private let phoneClientDisplayName: String
    private let now: @Sendable () -> Date
    private let initialState: MockAppState
    private var nostrAgentEventFactory: NostrAgentEventFactory
    private var nostrConfiguration: NostrAgentBridgeConfiguration
    private var nostrMessageSender: NostrAgentMessageSending?
    private var nostrMessageReceiver: NostrAgentMessageReceiving?
    private var nostrInboxTask: Task<Void, Never>?
    private var receivedNostrRelayEventIDs = Set<String>()

    public init(
        state: MockAppState = .preview,
        telemetry: TelemetryClient = OSLogTelemetryClient(),
        onboardingStore: OnboardingConfigurationStoring = InMemoryOnboardingConfigurationStore(),
        nostrConfiguration: NostrAgentBridgeConfiguration = .preview,
        nostrMessageSender: NostrAgentMessageSending? = nil,
        nostrMessageReceiver: NostrAgentMessageReceiving? = nil,
        nostrCredentialStore: NostrAgentBridgeCredentialStoring? = nil,
        nostrEntropy: any NostrEntropySource = SystemNostrEntropySource(),
        nostrRelayPublisher: any NostrRelayPublishing = NostrWebSocketRelayPublisher(),
        nostrRelaySubscriber: (any NostrRelaySubscribing)? = nil,
        nostrPlaintextEventSigner: NostrPlaintextRelayEventSigner = NostrPlaintextRelayEventSigner(),
        chatMessageRepository: any ChatMessagePersisting = InMemoryChatMessageRepository(),
        chatMessageRetentionPolicy: ChatMessageRetentionPolicy = .oneHour,
        phoneClientDisplayName: String = "Clawdia iPhone",
        now: @escaping @Sendable () -> Date = Date.init,
        initialDesktopPairingStatus: DesktopPairingStatus? = nil
    ) {
        let onboardingConfiguration = onboardingStore.loadConfiguration()
        var configuredState = state
        if onboardingConfiguration.didComplete {
            configuredState.configureInitialAreas(onboardingConfiguration.selectedAreas)
        }
        self.state = configuredState
        self.onboardingConfiguration = onboardingConfiguration
        self.telemetry = telemetry
        self.onboardingStore = onboardingStore
        self.initialState = state
        self.nostrAgentEventFactory = NostrAgentEventFactory(configuration: nostrConfiguration)
        self.nostrConfiguration = nostrConfiguration
        self.nostrMessageSender = nostrMessageSender
        self.nostrMessageReceiver = nostrMessageReceiver
        self.nostrCredentialStore = nostrCredentialStore
        self.nostrEntropy = nostrEntropy
        self.nostrRelayPublisher = nostrRelayPublisher
        self.nostrRelaySubscriber = nostrRelaySubscriber
        self.nostrPlaintextEventSigner = nostrPlaintextEventSigner
        self.chatMessageRepository = chatMessageRepository
        self.chatMessageRetentionPolicy = chatMessageRetentionPolicy
        self.phoneClientDisplayName = phoneClientDisplayName
        self.now = now
        self.desktopPairingStatus =
            initialDesktopPairingStatus ?? (nostrMessageSender == nil ? .notPaired : .paired(displayName: nil))
        loadPersistedChatMessages()
        telemetry.log("dev mode store initialized", area: .devMode)
        startNostrInboxListenerIfPossible()
    }

    deinit {
        nostrInboxTask?.cancel()
    }

    public func recordScreen(_ screen: DevScreen) {
        telemetry.metric(MetricEvent(name: "dev_screen_opened", area: .devMode, fields: ["screen": screen.rawValue]))
    }

    public func connectLocalhost(port: Int = 8787) {
        state.connection = .connected(.localhost(port: port))
        telemetry.metric(MetricEvent(name: "local_connection_selected", area: .localConnection, fields: ["port": "\(port)"]))
    }

    public func configureInitialAreas(_ areas: Set<LifeArea>) {
        completeOnboarding(selectedAreas: areas)
    }

    public func completeOnboarding(selectedAreas areas: Set<LifeArea>) {
        let configuration = OnboardingConfiguration(didComplete: true, selectedAreas: areas)
        state.configureInitialAreas(configuration.selectedAreas)
        onboardingConfiguration = configuration
        onboardingStore.saveConfiguration(configuration)
        telemetry.metric(MetricEvent(name: "initial_areas_configured", area: .devMode, fields: ["count": "\(areas.count)"]))
    }

    public func signOut() {
        let configuration = OnboardingConfiguration.fresh
        nostrInboxTask?.cancel()
        nostrInboxTask = nil
        receivedNostrRelayEventIDs.removeAll()
        state = initialState
        onboardingConfiguration = configuration
        onboardingStore.saveConfiguration(configuration)
        try? chatMessageRepository.deleteAll()
        try? nostrCredentialStore?.deleteCredentials()
        nostrAgentEventFactory = NostrAgentEventFactory()
        nostrConfiguration = .preview
        nostrMessageSender = nil
        nostrMessageReceiver = nil
        desktopPairingStatus = .notPaired
        telemetry.metric(MetricEvent(name: "signed_out", area: .devMode))
    }

    @discardableResult
    public func pairDesktop(with rawPairingCode: String) -> Bool {
        do {
            let payload = try NostrDesktopPairingPayload.parse(rawPairingCode)
            desktopPairingStatus = .connecting(displayName: payload.desktopName)
            let phonePrivateKeyHex = try makePhonePrivateKeyHex()
            let credentials = try NostrAgentBridgeCredentials(
                phonePrivateKeyHex: phonePrivateKeyHex,
                desktopPublicKeyHex: payload.desktopPublicKeyHex,
                relayURLs: payload.relayURLs,
                desktopDisplayName: payload.desktopName
            )
            try nostrCredentialStore?.saveCredentials(credentials)
            try configureNostrBridge(credentials: credentials)
            let acknowledgement = try preparePairingAcknowledgement(credentials: credentials)
            state.queuePreparedNostrRelayEvent(acknowledgement)
            publishPairingAcknowledgement(acknowledgement)
            desktopPairingStatus = .paired(displayName: payload.desktopName)
            telemetry.metric(MetricEvent(name: "nostr_desktop_pairing_completed", area: .devMode, fields: ["relay_count": "\(payload.relayURLs.count)"]))
            return true
        } catch {
            desktopPairingStatus = .failed(message: "The desktop pairing code could not be used. Scan the QR from Clawdia on your Mac and try again.")
            telemetry.metric(MetricEvent(name: "nostr_desktop_pairing_failed", area: .devMode, fields: ["error": String(describing: type(of: error))]))
            return false
        }
    }

    @discardableResult
    public func createCustomArea(named name: String) -> UserArea? {
        let area = state.createCustomArea(named: name)
        if let area {
            telemetry.metric(MetricEvent(name: "custom_area_created", area: .devMode, fields: ["name": area.name]))
        }
        return area
    }

    @discardableResult
    public func sendChatMessage(_ text: String, in chat: ChatPreview?) -> NostrOutboxEvent? {
        guard let chat else {
            return nil
        }
        let sentAt = now()
        let event = nostrAgentEventFactory.queueChatMessage(text: text, chat: chat, now: sentAt)
        let outgoingMessage = StoredChatMessage(
            id: event.id,
            conversationID: chat.id.uuidString,
            area: chat.area.rawValue,
            sender: .phone,
            text: text,
            createdAt: sentAt,
            expiresAt: chatMessageRetentionPolicy.expirationDate(for: sentAt),
            deliveryState: .sending
        )
        state.upsertChatMessage(outgoingMessage, now: sentAt)
        persistChatMessage(outgoingMessage)
        state.setAgentTyping(true, conversationID: chat.id.uuidString)
        state.queueOutgoingNostrEvent(event)
        if let nostrMessageSender {
            do {
                let prepared = try nostrMessageSender.send(event)
                updateChatMessageDeliveryState(id: event.id, deliveryState: .sent)
                state.queuePreparedNostrRelayEvent(prepared)
                telemetry.metric(
                    MetricEvent(
                        name: "nostr_relay_event_prepared",
                        area: .chat,
                        fields: ["kind": "\(prepared.kind)", "relay_count": "\(prepared.relayURLs.count)"]
                    )
                )
            } catch {
                updateChatMessageDeliveryState(id: event.id, deliveryState: .failed)
                state.setAgentTyping(false, conversationID: chat.id.uuidString)
                telemetry.metric(
                    MetricEvent(
                        name: "nostr_relay_event_prepare_failed",
                        area: .chat,
                        fields: ["error": String(describing: type(of: error))]
                    )
                )
            }
        } else {
            updateChatMessageDeliveryState(id: event.id, deliveryState: .failed)
            state.setAgentTyping(false, conversationID: chat.id.uuidString)
        }
        telemetry.metric(
            MetricEvent(
                name: "nostr_agent_event_queued",
                area: .chat,
                fields: [
                    "kind": "\(event.draft.kind)",
                    "area": chat.area.rawValue,
                    "relay_count": "\(event.relayURLs.count)"
                ]
            )
        )
        return event
    }

    @discardableResult
    public func receiveNostrRelayEvent(_ event: NostrPreparedRelayEvent) -> AgentMessageEnvelope? {
        guard let nostrMessageReceiver else {
            return nil
        }
        do {
            let envelope = try nostrMessageReceiver.receive(event)
            state.queueReceivedAgentMessage(envelope)
            storeReceivedAgentMessage(envelope)
            telemetry.metric(
                MetricEvent(
                    name: "nostr_agent_event_received",
                    area: .chat,
                    fields: [
                        "kind": envelope.kind.rawValue,
                        "area": envelope.area
                    ]
                )
            )
            return envelope
        } catch {
            telemetry.metric(
                MetricEvent(
                    name: "nostr_agent_event_receive_failed",
                    area: .chat,
                    fields: ["error": String(describing: type(of: error))]
                )
            )
            return nil
        }
    }

    private func loadPersistedChatMessages() {
        let currentDate = now()
        do {
            try chatMessageRepository.deleteExpired(before: currentDate)
            state.replaceChatMessages(
                try chatMessageRepository.loadActiveMessages(now: currentDate),
                now: currentDate
            )
        } catch {
            telemetry.metric(
                MetricEvent(
                    name: "chat_message_history_load_failed",
                    area: .chat,
                    fields: ["error": String(describing: type(of: error))]
                )
            )
        }
    }

    private func persistChatMessage(_ message: StoredChatMessage) {
        do {
            try chatMessageRepository.deleteExpired(before: now())
            try chatMessageRepository.save(message)
        } catch {
            telemetry.metric(
                MetricEvent(
                    name: "chat_message_persist_failed",
                    area: .chat,
                    fields: ["error": String(describing: type(of: error))]
                )
            )
        }
    }

    private func updateChatMessageDeliveryState(id: UUID, deliveryState: ChatMessageDeliveryState) {
        state.updateChatMessageDeliveryState(id: id, deliveryState: deliveryState)
        guard let message = state.chatMessages.first(where: { $0.id == id }) else {
            return
        }
        persistChatMessage(message)
    }

    private func storeReceivedAgentMessage(_ envelope: AgentMessageEnvelope) {
        let createdAt = Date(timeIntervalSince1970: TimeInterval(envelope.createdAt))
        let message = StoredChatMessage(
            id: envelope.id,
            conversationID: envelope.conversationID,
            area: envelope.area,
            sender: envelope.sender,
            text: envelope.text,
            createdAt: createdAt,
            expiresAt: chatMessageRetentionPolicy.expirationDate(for: createdAt),
            deliveryState: .received
        )
        state.upsertChatMessage(message, now: now())
        state.setAgentTyping(false, conversationID: envelope.conversationID)
        persistChatMessage(message)
    }

    private func makePhonePrivateKeyHex() throws -> String {
        for _ in 0..<8 {
            let privateKeyHex = try nostrEntropy.bytes(count: 32)
                .map { String(format: "%02x", $0) }
                .joined()
            if (try? NostrAgentKeypair(privateKeyHex: privateKeyHex)) != nil {
                return privateKeyHex
            }
        }
        throw NostrCryptoError.invalidPrivateKey
    }

    private func configureNostrBridge(credentials: NostrAgentBridgeCredentials) throws {
        let configuration = try credentials.bridgeConfiguration()
        nostrConfiguration = configuration
        nostrAgentEventFactory = NostrAgentEventFactory(configuration: configuration)
        nostrMessageSender = try NostrPublishingAgentMessageSender(phonePrivateKeyHex: credentials.phonePrivateKeyHex)
        nostrMessageReceiver = try NostrEncryptedAgentMessageReceiver(
            phonePrivateKeyHex: credentials.phonePrivateKeyHex,
            expectedSenderPublicKeyHex: credentials.desktopPublicKeyHex
        )
        startNostrInboxListenerIfPossible()
    }

    private func preparePairingAcknowledgement(credentials: NostrAgentBridgeCredentials) throws -> NostrPreparedRelayEvent {
        let configuration = try credentials.bridgeConfiguration()
        let draft = try NostrDesktopPairingAcknowledgement.draft(
            phonePublicKey: configuration.phonePublicKey,
            desktopPublicKey: configuration.desktopPublicKey,
            clientID: configuration.phonePublicKey,
            displayName: phoneClientDisplayName,
            createdAt: now()
        )
        return try nostrPlaintextEventSigner.sign(
            draft,
            privateKeyHex: credentials.phonePrivateKeyHex,
            relayURLs: configuration.relayURLs
        )
    }

    private func publishPairingAcknowledgement(_ acknowledgement: NostrPreparedRelayEvent) {
        let publisher = nostrRelayPublisher
        let telemetry = telemetry
        Task {
            let receipts = await publisher.publish(acknowledgement)
            telemetry.metric(
                MetricEvent(
                    name: "nostr_desktop_pairing_acknowledgement_published",
                    area: .devMode,
                    fields: [
                        "relay_count": "\(receipts.count)",
                        "accepted_count": "\(receipts.filter(\.accepted).count)"
                    ]
                )
            )
        }
    }

    private func startNostrInboxListenerIfPossible() {
        nostrInboxTask?.cancel()
        guard let nostrRelaySubscriber,
              nostrMessageReceiver != nil,
              !nostrConfiguration.relayURLs.isEmpty else {
            return
        }
        let subscription = NostrRelaySubscription(
            relayURLs: nostrConfiguration.relayURLs,
            recipientPublicKey: nostrConfiguration.phonePublicKey
        )
        let storeReference = WeakDevModeStoreReference(self)
        nostrInboxTask = Task { [nostrRelaySubscriber, subscription, storeReference] in
            while !Task.isCancelled {
                let events = await nostrRelaySubscriber.receiveOnce(subscription)
                var acceptedCount = 0
                for event in events {
                    let accepted = await MainActor.run {
                        storeReference.value?.acceptNostrInboxEventIfNew(event) ?? false
                    }
                    if accepted {
                        acceptedCount += 1
                    }
                }
                if acceptedCount == 0 {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
        }
    }

    @MainActor
    private func acceptNostrInboxEventIfNew(_ event: NostrPreparedRelayEvent) -> Bool {
        guard !receivedNostrRelayEventIDs.contains(event.id),
              receiveNostrRelayEvent(event) != nil else {
            return false
        }
        receivedNostrRelayEventIDs.insert(event.id)
        return true
    }
}

private final class WeakDevModeStoreReference: @unchecked Sendable {
    weak var value: DevModeStore?

    init(_ value: DevModeStore) {
        self.value = value
    }
}

public enum DesktopPairingStatus: Equatable, Sendable {
    case notPaired
    case connecting(displayName: String?)
    case paired(displayName: String?)
    case failed(message: String)
}
