import Foundation
import Testing

@testable import NessaFeatures

private func ready() -> [String: Any] {
  [
    "version": 1, "gatewayId": "gateway", "principalId": "owner", "organizationId": "org",
    "membershipId": "membership", "credentialId": "credential", "audienceId": "audience",
    "expiresAt": NSNull(), "methods": ["conversation.read", "", "conversation.read"],
    "grants": [["action": "record.read", "resource": ["organizationId": "org", "id": "gateway"]]],
  ]
}
private func decode(_ value: [String: Any]) throws -> GatewaySessionSnapshot {
  try JSONDecoder().decode(
    GatewayReadyDTO.self, from: JSONSerialization.data(withJSONObject: value)
  ).snapshot
}
@Test func readyPreservesIdentityRestrictionsAndExactSafeExpiry() throws {
  var wire = ready()
  wire["expiresAt"] = UInt64(9_007_199_254_740_991)
  let value = try decode(wire)
  #expect(value.identity.gatewayID == "gateway")
  #expect(value.identity.principalID == "owner")
  #expect(value.identity.organizationID == "org")
  #expect(value.identity.membershipID == "membership")
  #expect(value.identity.credentialID == "credential")
  #expect(value.identity.audienceID == "audience")
  #expect(value.expiresAt == 9_007_199_254_740_991)
  #expect(value.methods == ["conversation.read", "", "conversation.read"])
  #expect(value.grants[0].action == "record.read")
  #expect(value.grants[0].resource.organizationID == "org")
  #expect(value.grants[0].resource.id == "gateway")
  #expect(try decode(ready()).expiresAt == nil)
}
@Test func readyRejectsMissingEveryRequiredFieldAndUnknownNestedFields() throws {
  for key in ready().keys {
    var wire = ready()
    wire.removeValue(forKey: key)
    #expect(throws: (any Error).self) { try decode(wire) }
  }
  for location in ["ready", "grant", "resource"] {
    var wire = ready()
    var grant = (wire["grants"] as! [[String: Any]])[0]
    switch location {
    case "ready": wire["unexpected"] = 1
    case "grant":
      grant["unexpected"] = 1
      wire["grants"] = [grant]
    default:
      var resource = grant["resource"] as! [String: Any]
      resource["unexpected"] = 1
      grant["resource"] = resource
      wire["grants"] = [grant]
    }
    #expect(throws: (any Error).self) { try decode(wire) }
  }
}
@Test func readyRejectsInvalidBoundsAndUsesUnicodeScalars() throws {
  for (key, invalid): (String, Any) in [
    ("version", 2), ("version", true), ("principalId", ""),
    ("principalId", String(repeating: "a", count: 257)),
    ("principalId", String(repeating: "e\u{301}", count: 129)),
    ("expiresAt", -1), ("expiresAt", 1.5), ("expiresAt", UInt64(9_007_199_254_740_992)),
    ("grants", Array(repeating: (ready()["grants"] as! [[String: Any]])[0], count: 17)),
    ("methods", Array(repeating: "", count: 68)),
  ] {
    var wire = ready()
    wire[key] = invalid
    #expect(throws: (any Error).self) { try decode(wire) }
  }
  var wire = ready()
  wire["principalId"] = String(repeating: "e\u{301}", count: 128)
  wire["grants"] = []
  wire["methods"] = Array(repeating: "", count: 67)
  #expect(try decode(wire).identity.principalID == wire["principalId"] as? String)
  #expect(try decode(wire).methods.count == 67)
  for field in ["action", "organizationId", "id"] {
    var invalid = ready()
    var grant = (invalid["grants"] as! [[String: Any]])[0]
    if field == "action" {
      grant[field] = ""
    } else {
      var resource = grant["resource"] as! [String: Any]
      resource[field] = ""
      grant["resource"] = resource
    }
    invalid["grants"] = [grant]
    #expect(throws: (any Error).self) { try decode(invalid) }
  }
}
