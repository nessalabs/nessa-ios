import Foundation
import SharedKernel
import ClawdiaDesignSystem
import ClawdiaFeatures

struct VerificationFailure: Error, CustomStringConvertible {
    let description: String
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
    if !condition() {
        throw VerificationFailure(description: message)
    }
}

func testSharedKernel() throws {
    let value = NonEmptyString("  Clawdia  ")
    try expect(value.value == "Clawdia", "NonEmptyString should trim whitespace")

    let id = EntityID<String>()
    try expect(EntityID<String>(rawValue: id.rawValue) == id, "EntityID should round-trip raw values")
}

func testDesignSystemTokens() throws {
    try expect(ClawdiaColor.palette(.light).folders.count == 6, "light theme should expose six folder colors")
    try expect(ClawdiaColor.palette(.dark).folders.count == 6, "dark theme should expose six folder colors")
    try expect(ClawdiaSpacing.xs < ClawdiaSpacing.sm, "spacing scale xs < sm")
    try expect(ClawdiaSpacing.sm < ClawdiaSpacing.md, "spacing scale sm < md")
    try expect(ClawdiaSpacing.md < ClawdiaSpacing.lg, "spacing scale md < lg")
    try expect(ClawdiaSpacing.lg < ClawdiaSpacing.xl, "spacing scale lg < xl")
}

func testFeatureCatalog() throws {
    let titles = Set(DevScreen.allCases.map(\.title))
    let expected: Set<String> = [
        "Onboarding",
        "Home",
        "Chat",
        "Voice",
        "Approvals",
        "Search",
        "Calendar",
        "Folders",
        "Settings",
        "Connected Apps",
        "Memory",
        "Context Notes",
        "Context Board",
        "Design System"
    ]
    try expect(titles.isSuperset(of: expected), "dev screen catalog should cover all expected mock screens")

    let state = MockAppState.preview
    try expect(state.folders.count == 6, "preview state should contain six folders")
    try expect(state.chats.count >= 4, "preview state should contain chat rows")
    try expect(state.approvals.count >= ApprovalKind.allCases.count, "preview state should contain approval and diff examples")
    try expect(Set(state.approvals.map(\.kind)) == Set(ApprovalKind.allCases), "preview approvals should cover every approval kind")
    try expect(state.connection == .connected(.localhost(port: 8787)), "preview state should default to localhost connection")
}

func testAppFlowAreaConfiguration() throws {
    var state = MockAppState.preview

    state.configureInitialAreas([.personal, .work])

    try expect(state.folders.map(\.id) == [.personal, .work], "onboarding area selection should keep only chosen built-in areas")
    try expect(state.chats.allSatisfy { [.personal, .work].contains($0.area) }, "onboarding area selection should keep only chats for chosen areas")
}

func testAppFlowCustomAreaCreationAndFiltering() throws {
    var state = MockAppState.preview

    let created = state.createCustomArea(named: "  Side Projects  ")

    try expect(created?.name == "Side Projects", "custom area creation should trim whitespace")
    try expect(state.customAreas.count == 1, "custom area creation should update application state")
    try expect(state.availableAreaCount == state.folders.count + state.customAreas.count, "available area count should include built-in and custom areas")
    try expect(state.chats(matching: .life(.work)).allSatisfy { $0.area == .work }, "life-area filtering should return only matching chats")
    try expect(state.chats(matching: .all).count == state.chats.count, "all-area filtering should return every chat")

    if let created {
        try expect(state.chats(matching: .custom(created.id)).isEmpty, "new custom areas should start without associated chats")
    }
}

func testPreviewChatsAreScopedToAreas() throws {
    let state = MockAppState.preview

    for folder in state.folders {
        let areaChats = state.chats(matching: .life(folder.id))
        try expect(!areaChats.isEmpty, "\(folder.id.title) should have preview chats")
        try expect(folder.chatCount == areaChats.count, "\(folder.id.title) chat count should match its preview chats")
        try expect(areaChats.allSatisfy { $0.area == folder.id }, "\(folder.id.title) preview chats should stay in that area")
    }
}

func testAreaChatNavigationKeepsAreaRouteBehindChat() throws {
    let state = MockAppState.preview
    guard let homeChat = state.chats(matching: .life(.home)).first else {
        throw VerificationFailure(description: "Home should have a preview chat for route verification")
    }

    let path: [AppNavigationRoute] = [.area(.life(.home)), .chat(homeChat)]

    try expect(path.first == .area(.life(.home)), "area route should stay behind chat route")
    try expect(path.last == .chat(homeChat), "chat route should be pushed after its area route")
}

func testCalendarCurrentDateResolver() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let may8 = calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: 2026, month: 5, day: 8))!

    try expect(CalendarCurrentDateResolver.dayID(for: may8, calendar: calendar) == "2026-may-8", "calendar should resolve May 8, 2026 as the current demo day")
    try expect(CalendarCurrentDateResolver.monthKey(for: may8, calendar: calendar) == "may", "calendar should resolve the current month key")
}

func testLocalConnectionRequestShape() throws {
    let request = URLRequest.clawdiaHealthRequest(endpoint: .localhost(port: 8787), timeout: 2)

    try expect(request?.url?.absoluteString == "http://127.0.0.1:8787/health", "localhost health request should target the local Clawdia health route")
    try expect(request?.httpMethod == "GET", "localhost health request should use GET")
    try expect(request?.value(forHTTPHeaderField: "Accept") == "application/json", "localhost health request should accept JSON")
}

do {
    try testSharedKernel()
    try testDesignSystemTokens()
    try testFeatureCatalog()
    try testAppFlowAreaConfiguration()
    try testAppFlowCustomAreaCreationAndFiltering()
    try testPreviewChatsAreScopedToAreas()
    try testAreaChatNavigationKeepsAreaRouteBehindChat()
    try testCalendarCurrentDateResolver()
    try testLocalConnectionRequestShape()
    print("Clawdia verification tests passed")
} catch {
    fputs("Clawdia verification tests failed: \(error)\n", stderr)
    exit(1)
}
