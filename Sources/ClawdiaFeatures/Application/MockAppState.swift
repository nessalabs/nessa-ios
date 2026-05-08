import Foundation
public struct MockAppState: Equatable, Sendable {
    public var connection: ConnectionState
    public var folders: [FolderSummary]
    public var chats: [ChatPreview]
    public var approvals: [ApprovalRequest]

    public init(
        connection: ConnectionState,
        folders: [FolderSummary],
        chats: [ChatPreview],
        approvals: [ApprovalRequest]
    ) {
        self.connection = connection
        self.folders = folders
        self.chats = chats
        self.approvals = approvals
    }

    public static let preview = MockAppState(
        connection: .connected(.localhost(port: 8787)),
        folders: [
            FolderSummary(id: .personal, chatCount: 12, lastActivity: "2m"),
            FolderSummary(id: .work, chatCount: 8, lastActivity: "23m"),
            FolderSummary(id: .money, chatCount: 5, lastActivity: "1h"),
            FolderSummary(id: .health, chatCount: 3, lastActivity: "Tue"),
            FolderSummary(id: .home, chatCount: 7, lastActivity: "Yest"),
            FolderSummary(id: .travel, chatCount: 2, lastActivity: "Mar 4")
        ],
        chats: [
            ChatPreview(
                title: "Clawdia - Personal",
                preview: "I drafted a reply to your sister. Want to review before I send?",
                time: "2m",
                area: .personal,
                unread: true,
                pinned: true
            ),
            ChatPreview(
                title: "Q4 planning",
                preview: "You: ok let's tighten the deck before Thursday",
                time: "23m",
                area: .work
            ),
            ChatPreview(
                title: "Finances - weekly",
                preview: "Your spend is $84 under last week. Want a breakdown?",
                time: "1h",
                area: .money,
                unread: true
            ),
            ChatPreview(
                title: "Lisbon trip",
                preview: "Flight prices dropped. Lufthansa $612 for May 14.",
                time: "Yesterday",
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
