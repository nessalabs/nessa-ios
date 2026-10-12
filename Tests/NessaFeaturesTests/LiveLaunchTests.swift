import Testing

@testable import NessaFeatures

@Test @MainActor func liveTestLaunchRequiresLiveModeAndBothConnectionValues() {
  #if DEBUG
    let values = [
      "NESSA_TEST_GATEWAY_URL": "ws://127.0.0.1:18743/session",
      "NESSA_TEST_CREDENTIAL": "test-only",
    ]
    #expect(NessaDependencies.configured(environment: values).mode == .development)
    let live = NessaDependencies.configured(
      environment: values.merging(["NESSA_MODE": "live"]) { _, new in new })
    #expect(live.mode == .live)
    #expect(live.launchConnection?.address == values["NESSA_TEST_GATEWAY_URL"])
    #expect(live.launchConnection?.credential == "test-only")
    #expect(
      NessaDependencies.configured(environment: [
        "NESSA_MODE": "live", "NESSA_TEST_GATEWAY_URL": "ws://127.0.0.1:18743/session",
      ]).launchConnection == nil)
  #endif
}
