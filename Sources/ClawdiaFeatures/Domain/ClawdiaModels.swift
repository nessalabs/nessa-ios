import Foundation
import SharedKernel

public enum ClawdiaEndpoint: Equatable, Sendable {
    case localhost(port: Int)
    case cloud(URL)

    public var displayName: String {
        switch self {
        case .localhost(let port):
            "Localhost:\(port)"
        case .cloud(let url):
            url.host() ?? url.absoluteString
        }
    }
}

public enum ConnectionState: Equatable, Sendable {
    case disconnected
    case connecting(ClawdiaEndpoint)
    case connected(ClawdiaEndpoint)
    case failed(String)
}

public enum LifeArea: String, CaseIterable, Identifiable, Sendable {
    case personal
    case work
    case money
    case health
    case home
    case travel

    public var id: String { rawValue }

    public var title: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }

    public var icon: String {
        switch self {
        case .personal: "leaf"
        case .work: "diamond"
        case .money: "chart.pie"
        case .health: "sparkles"
        case .home: "house"
        case .travel: "airplane"
        }
    }
}

public struct FolderSummary: Identifiable, Equatable, Sendable {
    public let id: LifeArea
    public let chatCount: Int
    public let lastActivity: String

    public init(id: LifeArea, chatCount: Int, lastActivity: String) {
        self.id = id
        self.chatCount = chatCount
        self.lastActivity = lastActivity
    }
}

public struct ChatPreview: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let title: String
    public let preview: String
    public let time: String
    public let area: LifeArea
    public let unread: Bool
    public let pinned: Bool

    public init(
        id: UUID = UUID(),
        title: String,
        preview: String,
        time: String,
        area: LifeArea,
        unread: Bool = false,
        pinned: Bool = false
    ) {
        self.id = id
        self.title = title
        self.preview = preview
        self.time = time
        self.area = area
        self.unread = unread
        self.pinned = pinned
    }
}

public enum ApprovalKind: String, CaseIterable, Identifiable, Sendable {
    case draft
    case transfer
    case sendEmail
    case deleteArchive
    case codeDiff
    case documentDiff
    case calendarMove
    case settingsChange

    public var id: String { rawValue }
}

public struct ApprovalRequest: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let kind: ApprovalKind
    public let title: String
    public let detail: String
    public let primaryAction: String
    public let secondaryAction: String

    public init(
        id: UUID = UUID(),
        kind: ApprovalKind,
        title: String,
        detail: String,
        primaryAction: String,
        secondaryAction: String
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.primaryAction = primaryAction
        self.secondaryAction = secondaryAction
    }
}

public enum DevScreen: String, CaseIterable, Identifiable, Sendable {
    case onboarding
    case home
    case chat
    case voice
    case approvals
    case search
    case calendar
    case folders
    case settings
    case connectedApps
    case memory
    case contextNotes
    case contextBoard
    case designSystem

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .connectedApps: "Connected Apps"
        case .contextNotes: "Context Notes"
        case .contextBoard: "Context Board"
        case .designSystem: "Design System"
        default: rawValue.prefix(1).uppercased() + rawValue.dropFirst()
        }
    }
}

public protocol LocalClawdiaConnecting: Sendable {
    func connect(to endpoint: ClawdiaEndpoint) async -> ConnectionState
}
