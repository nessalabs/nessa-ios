import Foundation
import Testing
@testable import NessaFeatures

@MainActor
struct ExactConnectionTests {
  @Test func onlyReadinessCrossesIntoContract() throws {
    let dependencies = NessaDependencies.development()
    let bridge = ExactConnection(
      messages: dependencies.makeMessagesViewModel(), desktop: dependencies.makeDesktopLinkViewModel(),
      changed: {})
    #expect(bridge.state["hasCredential"] as? Bool == false)
    #expect(bridge.state["validCode"] as? Bool == false)

    bridge.address = "wss://example.test/session?token=private-endpoint"
    bridge.credential = "entered-secret"
    bridge.code = "ABCD-2345"
    let projected = try JSONSerialization.data(withJSONObject: bridge.state)
    let snapshot = String(decoding: projected, as: UTF8.self)
    #expect(bridge.state["hasCredential"] as? Bool == true)
    #expect(bridge.state["validCode"] as? Bool == true)
    #expect(!snapshot.contains("private-endpoint"))
    #expect(!snapshot.contains(bridge.credential))
    #expect(!snapshot.contains(bridge.code))
  }

  @Test func invalidOrStalePairingActionsLeaveTheLinkIdle() async {
    let dependencies = NessaDependencies.development()
    let bridge = ExactConnection(
      messages: dependencies.makeMessagesViewModel(), desktop: dependencies.makeDesktopLinkViewModel(),
      changed: {})
    bridge.code = "ABCD-2345"
    await bridge.perform("pair", key: "")
    await bridge.perform("choose", key: "previous-peer")
    await bridge.perform("forget", key: UUID().uuidString)
    #expect(bridge.state["phase"] as? String == "idle")
    #expect(bridge.state["linked"] as? Bool == false)
  }
}
