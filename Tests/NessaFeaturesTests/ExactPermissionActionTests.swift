import Testing
@testable import NessaFeatures

struct ExactPermissionActionTests {
  private func review(arguments: String = "{}", label: String = "Allow") -> NessaPermission {
    NessaPermission(review: "same-review", executionId: "turn", permissionId: "permission",
      title: "Run tool", toolName: "shell", argumentsJson: arguments,
      options: [.init(id: "allow", label: label, effect: "allow")])
  }

  @Test func threadAnswerAcceptsOnlyTheDisplayedRequestAndOfferedOption() {
    let displayed = review()
    let stamp = ExactPermissionAction.stamp(displayed, scope: 4, connection: 9)
    #expect(ExactPermissionAction.option("allow", stamp: stamp, review: displayed,
      scope: 4, connection: 9) == displayed.options[0])
    #expect(ExactPermissionAction.option("unknown", stamp: stamp, review: displayed,
      scope: 4, connection: 9) == nil)
    #expect(ExactPermissionAction.option("allow", stamp: "", review: displayed,
      scope: 4, connection: 9) == nil)
    // A replacement can reuse both review and option IDs, but is not the request shown.
    #expect(ExactPermissionAction.option("allow", stamp: stamp, review: review(arguments: "{\"changed\":true}"),
      scope: 4, connection: 9) == nil)
    #expect(ExactPermissionAction.option("allow", stamp: stamp, review: review(label: "Always allow"),
      scope: 4, connection: 9) == nil)
  }

  @Test func threadAnswerRejectsPreviousScopeOrConnection() {
    let displayed = review()
    let stamp = ExactPermissionAction.stamp(displayed, scope: 4, connection: 9)
    #expect(ExactPermissionAction.option("allow", stamp: stamp, review: displayed,
      scope: 5, connection: 9) == nil)
    #expect(ExactPermissionAction.option("allow", stamp: stamp, review: displayed,
      scope: 4, connection: 10) == nil)
  }
}
