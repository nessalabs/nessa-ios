import Foundation

public enum AreaFilter: Equatable, Hashable, Sendable {
    case all
    case life(LifeArea)
    case custom(UUID)
}

public struct MockAppState: Equatable, Sendable {
    public var connection: ConnectionState
    public var folders: [FolderSummary]
    public var customAreas: [UserArea]
    public var chats: [ChatPreview]
    public var approvals: [ApprovalRequest]
    public var receivedAgentMessages: [AgentMessageEnvelope]
    public var outgoingNostrEvents: [NostrOutboxEvent]
    public var preparedNostrRelayEvents: [NostrPreparedRelayEvent]

    public init(
        connection: ConnectionState,
        folders: [FolderSummary],
        customAreas: [UserArea] = [],
        chats: [ChatPreview],
        approvals: [ApprovalRequest],
        receivedAgentMessages: [AgentMessageEnvelope] = [],
        outgoingNostrEvents: [NostrOutboxEvent] = [],
        preparedNostrRelayEvents: [NostrPreparedRelayEvent] = []
    ) {
        self.connection = connection
        self.folders = folders
        self.customAreas = customAreas
        self.chats = chats
        self.approvals = approvals
        self.receivedAgentMessages = receivedAgentMessages
        self.outgoingNostrEvents = outgoingNostrEvents
        self.preparedNostrRelayEvents = preparedNostrRelayEvents
    }

    public var availableAreaCount: Int {
        folders.count + customAreas.count
    }

    public func chats(matching filter: AreaFilter) -> [ChatPreview] {
        switch filter {
        case .all:
            chats
        case .life(let area):
            chats.filter { $0.area == area }
        case .custom:
            []
        }
    }

    public mutating func configureInitialAreas(_ selectedAreas: Set<LifeArea>) {
        let configuredAreas = selectedAreas.isEmpty ? Set(LifeArea.allCases) : selectedAreas
        folders = folders.filter { configuredAreas.contains($0.id) }
        chats = chats.filter { configuredAreas.contains($0.area) }
    }

    @discardableResult
    public mutating func createCustomArea(named rawName: String) -> UserArea? {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        if let existing = customAreas.first(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            return existing
        }

        let area = UserArea(name: name)
        customAreas.append(area)
        return area
    }

    public mutating func queueOutgoingNostrEvent(_ event: NostrOutboxEvent) {
        outgoingNostrEvents.append(event)
    }

    public mutating func queuePreparedNostrRelayEvent(_ event: NostrPreparedRelayEvent) {
        preparedNostrRelayEvents.append(event)
    }

    public mutating func queueReceivedAgentMessage(_ envelope: AgentMessageEnvelope) {
        receivedAgentMessages.append(envelope)
    }

    public static let preview = MockAppState(
        connection: .connected(.localhost(port: 8787)),
        folders: [
            FolderSummary(id: .personal, chatCount: 2, lastActivity: "2m"),
            FolderSummary(id: .work, chatCount: 2, lastActivity: "23m"),
            FolderSummary(id: .money, chatCount: 2, lastActivity: "1h"),
            FolderSummary(id: .health, chatCount: 2, lastActivity: "Tue"),
            FolderSummary(id: .home, chatCount: 2, lastActivity: "Yest"),
            FolderSummary(id: .travel, chatCount: 2, lastActivity: "Mar 4")
        ],
        chats: [
            ChatPreview(
                title: "Mia's birthday",
                preview: "I drafted a reply to your sister. Want to review before I send?",
                time: "2m",
                area: .personal,
                unread: true,
                pinned: true
            ),
            ChatPreview(
                title: "Family check-in",
                preview: "Mom's appointment is Friday at 3 PM. I can remind you tomorrow.",
                time: "18m",
                area: .personal
            ),
            ChatPreview(
                title: "Q4 planning",
                preview: "You: ok let's tighten the deck before Thursday",
                time: "23m",
                area: .work
            ),
            ChatPreview(
                title: "Launch review",
                preview: "Three open decisions: pricing copy, support notes, and metrics owner.",
                time: "41m",
                area: .work,
                pinned: true
            ),
            ChatPreview(
                title: "Finances - weekly",
                preview: "Your spend is $84 under last week. Want a breakdown?",
                time: "1h",
                area: .money,
                unread: true
            ),
            ChatPreview(
                title: "Subscription cleanup",
                preview: "I found two annual renewals next week: storage and design tools.",
                time: "3h",
                area: .money
            ),
            ChatPreview(
                title: "Gym rhythm",
                preview: "You hit two workouts this week. Want me to hold Saturday morning?",
                time: "Tue",
                area: .health
            ),
            ChatPreview(
                title: "Sleep notes",
                preview: "Last night looked shorter. I can move tomorrow's deep work later.",
                time: "Tue",
                area: .health
            ),
            ChatPreview(
                title: "Apartment tasks",
                preview: "Filters, laundry, and the package pickup are still open.",
                time: "Yesterday",
                area: .home
            ),
            ChatPreview(
                title: "Grocery plan",
                preview: "I made a quick list around the dinners you saved this week.",
                time: "Yesterday",
                area: .home
            ),
            ChatPreview(
                title: "Lisbon trip",
                preview: "Flight prices dropped. Lufthansa $612 for May 14.",
                time: "Yesterday",
                area: .travel
            ),
            ChatPreview(
                title: "Packing list",
                preview: "Passport, adapter, rain shell, and camera batteries are still unchecked.",
                time: "Mar 4",
                area: .travel
            )
        ],
        approvals: [
            ApprovalRequest(
                kind: .draft,
                title: "Draft for Mia - birthday card",
                detail: "Warm and funny birthday note with a review step before saving.",
                primaryAction: "Approve and save",
                secondaryAction: "Request changes"
            ),
            ApprovalRequest(
                kind: .transfer,
                title: "Spending alert - approve transfer",
                detail: "Move $1,200 from Checking to Travel savings for Lisbon.",
                primaryAction: "Approve transfer",
                secondaryAction: "Request changes"
            ),
            ApprovalRequest(
                kind: .sendEmail,
                title: "Send email to Marcus",
                detail: "Reply to Marcus with the revised PR approach.",
                primaryAction: "Slide to send",
                secondaryAction: "Cancel"
            ),
            ApprovalRequest(
                kind: .deleteArchive,
                title: "Delete archive - 14 chats",
                detail: "Permanent cleanup of old work threads from Q3 2025.",
                primaryAction: "Hold to confirm",
                secondaryAction: "Cancel"
            ),
            ApprovalRequest(
                kind: .codeDiff,
                title: "trip-planner.ts - 2 hunks",
                detail: "+3 -2 with accept-all or per-line review.",
                primaryAction: "Accept all",
                secondaryAction: "Review per-line"
            ),
            ApprovalRequest(
                kind: .documentDiff,
                title: "Paragraph 3 - proposal.md",
                detail: "Track-changes rewrite with Clawdia's reasoning attached.",
                primaryAction: "Accept rewrite",
                secondaryAction: "Edit manually"
            ),
            ApprovalRequest(
                kind: .calendarMove,
                title: "Move Design crit",
                detail: "Move from Wed 2 PM to Thu 11 AM with no conflicts.",
                primaryAction: "Move it",
                secondaryAction: "Pick another time"
            ),
            ApprovalRequest(
                kind: .settingsChange,
                title: "Notification rules - 3 changes",
                detail: "Quiet hours, approvals only, and Slack alert scope are staged for review.",
                primaryAction: "Apply changes",
                secondaryAction: "Show each one"
            )
        ]
    )
}
