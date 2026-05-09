import Foundation

public enum IPhoneDataConnectionKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case iCloud
    case health
    case location

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .iCloud: "iCloud"
        case .health: "Health"
        case .location: "Location"
        }
    }

    public var summary: String {
        switch self {
        case .iCloud:
            "Sync iPhone chat history and settings across your Apple devices."
        case .health:
            "Allow Clawdia to gather available Health samples for desktop analysis."
        case .location:
            "Allow Clawdia to include location context in desktop analysis."
        }
    }
}

public enum IPhoneDataConnectionStatus: String, Codable, Equatable, Sendable {
    case unavailable
    case notDetermined
    case requesting
    case connected
    case denied

    public var settingsLabel: String {
        switch self {
        case .unavailable: "Unavailable"
        case .notDetermined: "Ask"
        case .requesting: "Asking"
        case .connected: "On"
        case .denied: "Off"
        }
    }
}

public struct IPhoneDataConnection: Identifiable, Codable, Equatable, Sendable {
    public let kind: IPhoneDataConnectionKind
    public var status: IPhoneDataConnectionStatus
    public var includeInDesktopAnalysis: Bool

    public var id: IPhoneDataConnectionKind { kind }

    public init(
        kind: IPhoneDataConnectionKind,
        status: IPhoneDataConnectionStatus,
        includeInDesktopAnalysis: Bool
    ) {
        self.kind = kind
        self.status = status
        self.includeInDesktopAnalysis = includeInDesktopAnalysis
    }

    public static func defaults() -> [IPhoneDataConnection] {
        IPhoneDataConnectionKind.allCases.map { kind in
            IPhoneDataConnection(
                kind: kind,
                status: .notDetermined,
                includeInDesktopAnalysis: false
            )
        }
    }
}

public protocol IPhoneDataConnectionProviding: Sendable {
    func loadConnections() async -> [IPhoneDataConnection]
    func requestConnection(_ kind: IPhoneDataConnectionKind) async -> IPhoneDataConnection
}

public struct StaticIPhoneDataConnectionProvider: IPhoneDataConnectionProviding {
    private let connections: [IPhoneDataConnection]

    public init(connections: [IPhoneDataConnection] = IPhoneDataConnection.defaults()) {
        self.connections = connections
    }

    public func loadConnections() async -> [IPhoneDataConnection] {
        connections
    }

    public func requestConnection(_ kind: IPhoneDataConnectionKind) async -> IPhoneDataConnection {
        connections.first(where: { $0.kind == kind }) ?? IPhoneDataConnection(
            kind: kind,
            status: .unavailable,
            includeInDesktopAnalysis: false
        )
    }
}
