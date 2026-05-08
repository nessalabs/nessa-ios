import ClawdiaObservability

public struct ConnectToClawdiaUseCase: Sendable {
    private let connector: LocalClawdiaConnecting
    private let telemetry: TelemetryClient

    public init(connector: LocalClawdiaConnecting, telemetry: TelemetryClient = OSLogTelemetryClient()) {
        self.connector = connector
        self.telemetry = telemetry
    }

    public func callAsFunction(endpoint: ClawdiaEndpoint) async -> ConnectionState {
        telemetry.metric(MetricEvent(name: "connection_attempt_started", area: .localConnection, fields: ["endpoint": endpoint.displayName]))
        let state = await connector.connect(to: endpoint)
        telemetry.metric(MetricEvent(name: "connection_attempt_finished", area: .localConnection, fields: ["state": state.metricValue]))
        return state
    }
}

private extension ConnectionState {
    var metricValue: String {
        switch self {
        case .disconnected:
            "disconnected"
        case .connecting:
            "connecting"
        case .connected:
            "connected"
        case .failed:
            "failed"
        }
    }
}
