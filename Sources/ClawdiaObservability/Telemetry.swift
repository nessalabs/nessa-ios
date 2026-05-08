import Foundation
import OSLog
import SharedKernel

public enum TelemetryArea: String, Sendable {
    case app
    case designSystem
    case onboarding
    case chat
    case localConnection
    case devMode
}

public struct MetricEvent: Equatable, Sendable {
    public let name: String
    public let area: TelemetryArea
    public let fields: [String: String]

    public init(name: String, area: TelemetryArea, fields: [String: String] = [:]) {
        self.name = name
        self.area = area
        self.fields = fields
    }
}

public protocol TelemetryClient: Sendable {
    func log(_ message: String, area: TelemetryArea)
    func metric(_ event: MetricEvent)
}

public struct OSLogTelemetryClient: TelemetryClient {
    private let subsystem: String

    public init(subsystem: String = "com.clawdia.mobile") {
        self.subsystem = subsystem
    }

    public func log(_ message: String, area: TelemetryArea) {
        Logger(subsystem: subsystem, category: area.rawValue).info("\(message, privacy: .public)")
    }

    public func metric(_ event: MetricEvent) {
        let fields = event.fields
            .map { "\($0.key)=\($0.value)" }
            .sorted()
            .joined(separator: " ")
        Logger(subsystem: subsystem, category: event.area.rawValue)
            .notice("metric \(event.name, privacy: .public) \(fields, privacy: .public)")
    }
}

public actor InMemoryTelemetryClient: TelemetryClient {
    public private(set) var logs: [(String, TelemetryArea)] = []
    public private(set) var metrics: [MetricEvent] = []

    public init() {}

    nonisolated public func log(_ message: String, area: TelemetryArea) {
        Task { await appendLog(message, area: area) }
    }

    nonisolated public func metric(_ event: MetricEvent) {
        Task { await appendMetric(event) }
    }

    private func appendLog(_ message: String, area: TelemetryArea) {
        logs.append((message, area))
    }

    private func appendMetric(_ event: MetricEvent) {
        metrics.append(event)
    }
}
