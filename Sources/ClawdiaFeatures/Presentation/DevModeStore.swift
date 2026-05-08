import SwiftUI
import ClawdiaObservability

public final class DevModeStore: ObservableObject {
    @Published public private(set) var state: MockAppState
    private let telemetry: TelemetryClient
    private let nostrAgentEventFactory: NostrAgentEventFactory
    private let nostrMessageSender: NostrAgentMessageSending?
    private let nostrMessageReceiver: NostrAgentMessageReceiving?

    public init(
        state: MockAppState = .preview,
        telemetry: TelemetryClient = OSLogTelemetryClient(),
        nostrConfiguration: NostrAgentBridgeConfiguration = .preview,
        nostrMessageSender: NostrAgentMessageSending? = nil,
        nostrMessageReceiver: NostrAgentMessageReceiving? = nil
    ) {
        self.state = state
        self.telemetry = telemetry
        self.nostrAgentEventFactory = NostrAgentEventFactory(configuration: nostrConfiguration)
        self.nostrMessageSender = nostrMessageSender
        self.nostrMessageReceiver = nostrMessageReceiver
        telemetry.log("dev mode store initialized", area: .devMode)
    }

    public func recordScreen(_ screen: DevScreen) {
        telemetry.metric(MetricEvent(name: "dev_screen_opened", area: .devMode, fields: ["screen": screen.rawValue]))
    }

    public func connectLocalhost(port: Int = 8787) {
        state.connection = .connected(.localhost(port: port))
        telemetry.metric(MetricEvent(name: "local_connection_selected", area: .localConnection, fields: ["port": "\(port)"]))
    }

    public func configureInitialAreas(_ areas: Set<LifeArea>) {
        state.configureInitialAreas(areas)
        telemetry.metric(MetricEvent(name: "initial_areas_configured", area: .devMode, fields: ["count": "\(areas.count)"]))
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
        let event = nostrAgentEventFactory.queueChatMessage(text: text, chat: chat)
        state.queueOutgoingNostrEvent(event)
        if let nostrMessageSender {
            do {
                let prepared = try nostrMessageSender.send(event)
                state.queuePreparedNostrRelayEvent(prepared)
                telemetry.metric(
                    MetricEvent(
                        name: "nostr_relay_event_prepared",
                        area: .chat,
                        fields: ["kind": "\(prepared.kind)", "relay_count": "\(prepared.relayURLs.count)"]
                    )
                )
            } catch {
                telemetry.metric(
                    MetricEvent(
                        name: "nostr_relay_event_prepare_failed",
                        area: .chat,
                        fields: ["error": String(describing: type(of: error))]
                    )
                )
            }
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
}
