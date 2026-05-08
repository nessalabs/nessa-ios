import SwiftUI
import ClawdiaObservability

public final class DevModeStore: ObservableObject {
    @Published public private(set) var state: MockAppState
    private let telemetry: TelemetryClient

    public init(state: MockAppState = .preview, telemetry: TelemetryClient = OSLogTelemetryClient()) {
        self.state = state
        self.telemetry = telemetry
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
}
