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
    try testLocalConnectionRequestShape()
    print("Clawdia verification tests passed")
} catch {
    fputs("Clawdia verification tests failed: \(error)\n", stderr)
    exit(1)
}
