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
    public var chatMessages: [StoredChatMessage]
    public var agentTypingConversationIDs: Set<String>
    public var iPhoneDataConnections: [IPhoneDataConnection]
    public var receivedAgentMessages: [AgentMessageEnvelope]
    public var outgoingNostrEvents: [NostrOutboxEvent]
    public var preparedNostrRelayEvents: [NostrPreparedRelayEvent]

    public init(
        connection: ConnectionState,
        folders: [FolderSummary],
        customAreas: [UserArea] = [],
        chats: [ChatPreview],
        approvals: [ApprovalRequest],
        chatMessages: [StoredChatMessage] = [],
        agentTypingConversationIDs: Set<String> = [],
        iPhoneDataConnections: [IPhoneDataConnection] = IPhoneDataConnection.defaults(),
        receivedAgentMessages: [AgentMessageEnvelope] = [],
        outgoingNostrEvents: [NostrOutboxEvent] = [],
        preparedNostrRelayEvents: [NostrPreparedRelayEvent] = []
    ) {
        self.connection = connection
        self.folders = folders
        self.customAreas = customAreas
        self.chats = chats
        self.approvals = approvals
        self.chatMessages = chatMessages
        self.agentTypingConversationIDs = agentTypingConversationIDs
        self.iPhoneDataConnections = iPhoneDataConnections
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

    public mutating func replaceChatMessages(_ messages: [StoredChatMessage], now: Date = Date()) {
        chatMessages = messages.filter { !$0.isExpired(now: now) }
        refreshChatPreviews()
    }

    public mutating func upsertChatMessage(_ message: StoredChatMessage, now: Date = Date()) {
        guard !message.isExpired(now: now) else {
            chatMessages.removeAll { $0.id == message.id }
            refreshChatPreviews()
            return
        }

        if let index = chatMessages.firstIndex(where: { $0.id == message.id }) {
            chatMessages[index] = message
        } else {
            chatMessages.append(message)
        }
        refreshChatPreviews()
    }

    public mutating func updateChatMessageDeliveryState(id: UUID, deliveryState: ChatMessageDeliveryState) {
        guard let index = chatMessages.firstIndex(where: { $0.id == id }) else {
            return
        }
        chatMessages[index].deliveryState = deliveryState
        refreshChatPreviews()
    }

    public mutating func pruneExpiredChatMessages(now: Date) {
        chatMessages.removeAll { $0.isExpired(now: now) }
        refreshChatPreviews()
    }

    public mutating func deleteChatMessages(ids: Set<UUID>) {
        guard !ids.isEmpty else {
            return
        }
        chatMessages.removeAll { ids.contains($0.id) }
        receivedAgentMessages.removeAll { ids.contains($0.id) }
        refreshChatPreviews()
    }

    @discardableResult
    public mutating func deleteChat(id: UUID) -> Bool {
        guard let chat = chats.first(where: { $0.id == id }) else {
            return false
        }
        let conversationID = chat.id.uuidString
        chats.removeAll { $0.id == id }
        chatMessages.removeAll { $0.conversationID == conversationID }
        receivedAgentMessages.removeAll { $0.conversationID == conversationID }
        agentTypingConversationIDs.remove(conversationID)
        refreshFolderChatCounts()
        return true
    }

    @discardableResult
    public mutating func deleteArea(_ area: AreaFilter) -> Bool {
        switch area {
        case .all:
            return false
        case .life(let lifeArea):
            let removedChatIDs = Set(chats.filter { $0.area == lifeArea }.map { $0.id.uuidString })
            folders.removeAll { $0.id == lifeArea }
            chats.removeAll { $0.area == lifeArea }
            chatMessages.removeAll { $0.area == lifeArea.rawValue || removedChatIDs.contains($0.conversationID) }
            receivedAgentMessages.removeAll { $0.area == lifeArea.rawValue || removedChatIDs.contains($0.conversationID) }
            agentTypingConversationIDs.subtract(removedChatIDs)
            refreshFolderChatCounts()
            return true
        case .custom(let id):
            let beforeCount = customAreas.count
            customAreas.removeAll { $0.id == id }
            return beforeCount != customAreas.count
        }
    }

    public func chatMessages(conversationID: String?) -> [StoredChatMessage] {
        chatMessages
            .filter { message in
                conversationID == nil || message.conversationID == conversationID
            }
            .sorted { left, right in
                if left.createdAt == right.createdAt {
                    return left.id.uuidString < right.id.uuidString
                }
                return left.createdAt < right.createdAt
            }
    }

    public mutating func setAgentTyping(_ isTyping: Bool, conversationID: String) {
        if isTyping {
            agentTypingConversationIDs.insert(conversationID)
        } else {
            agentTypingConversationIDs.remove(conversationID)
        }
    }

    public func isAgentTyping(conversationID: String?) -> Bool {
        guard let conversationID else {
            return false
        }
        return agentTypingConversationIDs.contains(conversationID)
    }

    public mutating func replaceIPhoneDataConnections(_ connections: [IPhoneDataConnection]) {
        let existingByKind = Dictionary(uniqueKeysWithValues: iPhoneDataConnections.map { ($0.kind, $0) })
        iPhoneDataConnections = IPhoneDataConnectionKind.allCases.map { kind in
            let incoming = connections.first(where: { $0.kind == kind }) ?? IPhoneDataConnection(
                kind: kind,
                status: .unavailable,
                includeInDesktopAnalysis: false
            )
            guard let existing = existingByKind[kind] else {
                return incoming
            }
            if existing.status == .connected && incoming.status == .notDetermined {
                return existing
            }
            if existing.status == .requesting && incoming.status == .notDetermined {
                return existing
            }
            return incoming
        }
    }

    public mutating func updateIPhoneDataConnection(_ connection: IPhoneDataConnection) {
        if let index = iPhoneDataConnections.firstIndex(where: { $0.kind == connection.kind }) {
            iPhoneDataConnections[index] = connection
        } else {
            iPhoneDataConnections.append(connection)
            replaceIPhoneDataConnections(iPhoneDataConnections)
        }
    }

    private mutating func refreshChatPreviews() {
        let latestMessages = Dictionary(grouping: chatMessages, by: \.conversationID)
            .compactMapValues { messages in
                messages.max { left, right in
                    if left.createdAt == right.createdAt {
                        return left.id.uuidString < right.id.uuidString
                    }
                    return left.createdAt < right.createdAt
                }
            }

        chats = chats.map { chat in
            guard let latest = latestMessages[chat.id.uuidString] else {
                return ChatPreview(
                    id: chat.id,
                    title: chat.title,
                    preview: defaultPreview(for: chat),
                    time: chat.time,
                    area: chat.area,
                    unread: false,
                    pinned: chat.pinned
                )
            }
            return ChatPreview(
                id: chat.id,
                title: chat.title,
                preview: latest.sender == .phone ? "You: \(latest.text)" : latest.text,
                time: "Now",
                area: chat.area,
                unread: latest.sender != .phone,
                pinned: chat.pinned
            )
        }
        refreshFolderChatCounts()
    }

    private mutating func refreshFolderChatCounts() {
        folders = folders.map { folder in
            let count = chats.filter { $0.area == folder.id }.count
            return FolderSummary(
                id: folder.id,
                chatCount: count,
                lastActivity: count == 0 ? "No chats" : folder.lastActivity
            )
        }
    }

    private func defaultPreview(for chat: ChatPreview) -> String {
        if chat.title == "Clawdia" {
            return "Send a message to Clawdia on your Mac."
        }
        return "No local messages."
    }

    public static let production = MockAppState(
        connection: .disconnected,
        folders: LifeArea.allCases.map { area in
            FolderSummary(id: area, chatCount: 1, lastActivity: "Now")
        },
        chats: LifeArea.allCases.map { area in
            ChatPreview(
                id: area.defaultChatID,
                title: "Clawdia",
                preview: "Send a message to Clawdia on your Mac.",
                time: "Now",
                area: area,
                pinned: true
            )
        },
        approvals: []
    )

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
