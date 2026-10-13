import Foundation
import Testing

@testable import NessaFeatures

func pairingWireStatus() -> [String: Any] {
  [
    "invitationId": Array(0..<16), "consentId": Array(16..<32), "generation": UInt64.max,
    "class": "a-future-published-class",
    "grant": [
      "action": "conversation.read", "resource": ["organizationId": "org", "id": "gateway"],
    ],
    "createdAtMs": UInt64(9_007_199_254_740_993), "expiresAtMs": UInt64.max, "phase": "terminal",
    "claimedDeviceKey": Array(0..<32), "credentialId": "credential",
    "receiver": ["receiverId": "receiver", "accessEpoch": UInt64.max],
    "terminal": [
      "cause": "credential_revoked", "initiator": ["kind": "principal", "principalId": "owner"],
    ], "cleanupPending": true,
  ]
}
private func decodePairing<T: Decodable>(_ type: T.Type, _ wire: [String: Any]) throws -> T {
  try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: wire))
}
@Test func pairingStatusPreservesCompleteIndependentEvidence() throws {
  let v = try decodePairing(GatewayPairingStatusDTO.self, pairingWireStatus()).value
  #expect(v.invitationID == Data(0..<16))
  #expect(v.consentID == Data(16..<32))
  #expect(v.generation == UInt64.max)
  #expect(v.consentClass == "a-future-published-class")
  #expect(
    v.grant
      == .init(action: "conversation.read", resource: .init(organizationID: "org", id: "gateway")))
  #expect(v.createdAtMs == 9_007_199_254_740_993)
  #expect(v.expiresAtMs == UInt64.max)
  #expect(v.phase == .terminal)
  #expect(v.claimedDeviceKey == Data(0..<32))
  #expect(v.credentialID == "credential")
  #expect(v.receiver == .init(id: "receiver", accessEpoch: UInt64.max))
  #expect(v.terminal == .init(cause: .credentialRevoked, initiator: .principal("owner")))
  #expect(v.cleanupPending)
  #expect(try JSONDecoder().decode(GatewayPairingStatus.self, from: JSONEncoder().encode(v)) == v)
}
@Test func pairingOmittedOptionalsAreAcceptedButNullIsRefused() throws {
  for key in ["claimedDeviceKey", "credentialId", "receiver", "terminal"] {
    var wire = pairingWireStatus()
    wire.removeValue(forKey: key)
    _ = try decodePairing(GatewayPairingStatusDTO.self, wire)
    wire[key] = NSNull()
    #expect(throws: (any Error).self) { try decodePairing(GatewayPairingStatusDTO.self, wire) }
  }
  #expect(
    try decodePairing(GatewayPairingApprovalDTO.self, ["status": pairingWireStatus()]).value
      .activationStopped == nil)
  #expect(throws: (any Error).self) {
    try decodePairing(
      GatewayPairingApprovalDTO.self,
      ["status": pairingWireStatus(), "activationStopped": NSNull()])
  }
}
@Test func pairingRefusesMissingRequiredAndUnknownNestedFields() throws {
  let optional: Set<String> = ["claimedDeviceKey", "credentialId", "receiver", "terminal"]
  for key in pairingWireStatus().keys where !optional.contains(key) {
    var wire = pairingWireStatus()
    wire.removeValue(forKey: key)
    #expect(throws: (any Error).self) { try decodePairing(GatewayPairingStatusDTO.self, wire) }
  }
  for key in ["status", "receiver", "terminal", "initiator", "grant", "resource"] {
    var wire = pairingWireStatus()
    if key == "status" {
      wire["unexpected"] = true
    } else if key == "initiator" {
      var terminal = wire["terminal"] as! [String: Any]
      var initiator = terminal["initiator"] as! [String: Any]
      initiator["unexpected"] = true
      terminal["initiator"] = initiator
      wire["terminal"] = terminal
    } else if key == "resource" {
      var grant = wire["grant"] as! [String: Any]
      var resource = grant["resource"] as! [String: Any]
      resource["unexpected"] = true
      grant["resource"] = resource
      wire["grant"] = grant
    } else {
      var nested = wire[key] as! [String: Any]
      nested["unexpected"] = true
      wire[key] = nested
    }
    #expect(throws: (any Error).self) { try decodePairing(GatewayPairingStatusDTO.self, wire) }
  }
}
@Test func pairingIntegerAndByteBoundsUseExactUnsignedWireValues() throws {
  for key in ["generation", "createdAtMs", "expiresAtMs"] {
    for bad: Any in [-1, 1.5, true, "1", NSNull()] {
      var wire = pairingWireStatus()
      wire[key] = bad
      #expect(throws: (any Error).self) { try decodePairing(GatewayPairingStatusDTO.self, wire) }
    }
    var wire = pairingWireStatus()
    wire[key] = 0
    if key == "generation" {
      #expect(throws: (any Error).self) { try decodePairing(GatewayPairingStatusDTO.self, wire) }
    } else {
      _ = try decodePairing(GatewayPairingStatusDTO.self, wire)
    }
  }
  for bad: Any in [0, -1, 1.5, true] {
    var wire = pairingWireStatus()
    wire["receiver"] = ["receiverId": "receiver", "accessEpoch": bad]
    #expect(throws: (any Error).self) { try decodePairing(GatewayPairingStatusDTO.self, wire) }
  }
  let raw = String(
    decoding: try JSONSerialization.data(withJSONObject: pairingWireStatus()), as: UTF8.self)
  #expect(throws: (any Error).self) {
    try JSONDecoder().decode(
      GatewayPairingStatusDTO.self,
      from: Data(
        raw.replacingOccurrences(of: "18446744073709551615", with: "18446744073709551616").utf8))
  }
  for key in ["invitationId", "consentId", "claimedDeviceKey"] {
    let count = key == "claimedDeviceKey" ? 32 : 16
    for bad: Any in [
      Array(repeating: 0, count: count - 1), Array(repeating: 0, count: count + 1),
      Array(repeating: 256, count: count), Array(repeating: -1, count: count),
      Array(repeating: true, count: count), Array(repeating: 1.5, count: count), "AA==",
    ] {
      var wire = pairingWireStatus()
      wire[key] = bad
      #expect(throws: (any Error).self) { try decodePairing(GatewayPairingStatusDTO.self, wire) }
    }
  }
}
@Test func pairingInitiatorUsesExactDiscriminatedActor() throws {
  let valid: [([String: Any], GatewayPairingStatus.Initiator)] = [
    (["kind": "local_operator"], .localOperator), (["kind": "system"], .system),
    (["kind": "principal", "principalId": "owner"], .principal("owner")),
    (["kind": "device", "deviceKey": Array(0..<32)], .device(Data(0..<32))),
  ]
  for (actor, expected) in valid {
    var wire = pairingWireStatus()
    wire["terminal"] = ["cause": "expired", "initiator": actor]
    #expect(
      try decodePairing(GatewayPairingStatusDTO.self, wire).value.terminal?.initiator == expected)
  }
  for actor: [String: Any] in [
    ["kind": "principal"], ["kind": "device"], ["kind": "system", "principalId": "owner"],
    ["kind": "local_operator", "deviceKey": Array(0..<32)],
    ["kind": "device", "deviceKey": Array(0..<32), "principalId": "owner"], ["kind": "future"],
  ] {
    var wire = pairingWireStatus()
    wire["terminal"] = ["cause": "expired", "initiator": actor]
    #expect(throws: (any Error).self) { try decodePairing(GatewayPairingStatusDTO.self, wire) }
  }
}
@Test func pairingCodeIsOnlyLengthCheckedAndPendingHasNoInventedCap() throws {
  let created = try decodePairing(
    GatewayPairingCreatedDTO.self, ["code": "👩👩👩👩👩👩👩👩👩", "status": pairingWireStatus()]
  ).value
  #expect(created.code.unicodeScalars.count == 9)
  for code in ["", "ABCD-EFG", "ABCD-EFGHI"] {
    #expect(throws: (any Error).self) {
      try decodePairing(
        GatewayPairingCreatedDTO.self, ["code": code, "status": pairingWireStatus()])
    }
  }
  #expect(
    try decodePairing(
      GatewayPairingPendingDTO.self, ["items": Array(repeating: pairingWireStatus(), count: 100)]
    ).values.count == 100)
  for stop in ["retryable", "permanent"] {
    #expect(
      try decodePairing(
        GatewayPairingApprovalDTO.self, ["status": pairingWireStatus(), "activationStopped": stop]
      ).value.activationStopped?.rawValue == stop)
  }
  #expect(throws: (any Error).self) {
    try decodePairing(
      GatewayPairingApprovalDTO.self,
      ["status": pairingWireStatus(), "activationStopped": "future"])
  }
}
@Test func pairingResponseGrammarRefusesBooleanCoercionAndContradictions() throws {
  for wire: [String: Any] in [
    ["type": "res", "id": "1", "payload": [:]],
    ["type": "res", "id": "1", "ok": 1, "payload": [:]],
    ["type": "res", "id": "1", "ok": true],
    [
      "type": "res", "id": "1", "ok": true, "payload": [:],
      "error": ["code": "forbidden", "message": ""],
    ],
    ["type": "res", "id": "1", "ok": false, "error": ["message": "forbidden"]],
    ["type": "res", "id": "1", "ok": false, "error": ["code": "", "message": ""]],
    ["type": "res", "id": "1", "ok": false, "error": ["code": "forbidden", "message": NSNull()]],
    [
      "type": "res", "id": "1", "ok": false,
      "error": ["code": "forbidden", "message": "", "extra": true],
    ],
    [
      "type": "res", "id": "1", "ok": false, "error": ["code": "forbidden", "message": ""],
      "payload": [:],
    ],
    ["type": "res", "id": "1", "ok": true, "payload": [:], "extra": true],
  ] {
    #expect(throws: (any Error).self) { try decodePairing(GatewayPairingEnvelope.self, wire) }
  }
  _ = try decodePairing(
    GatewayPairingEnvelope.self,
    [
      "type": "res", "id": "1", "ok": false,
      "error": ["code": "forbidden", "message": "", "details": NSNull()],
    ])
}
@Test func pairingOpaqueEqualityPreservesUtf8() {
  #expect(
    GatewayPairingStatus.Receiver(id: "é", accessEpoch: 1) != .init(id: "e\u{301}", accessEpoch: 1))
  #expect(GatewayPairingStatus.Initiator.principal("é") != .principal("e\u{301}"))
}

@Test func pairingRefusalBehaviorUsesOnlyWireCode() {
  for diagnostic in ["", "active", "credential_revoked", "retryable", "cancelled"] {
    let rejection = GatewayPairingRejection(code: "forbidden", diagnostic: diagnostic, details: nil)
    guard case .forbidden = rejection.kind else {
      Issue.record("Diagnostic changed refusal behavior")
      continue
    }
    #expect(rejection.diagnostic == diagnostic)
  }
  for (code, tag) in [("invalid_request", 1), ("unknown_method", 2), ("future_error", 3)] {
    let rejection = GatewayPairingRejection(
      code: code, diagnostic: "pairing_not_found", details: Data("null".utf8))
    switch (rejection.kind, tag) {
    case (.invalidRequest, 1), (.unknownMethod, 2): break
    case (.unknown(let original), 3): #expect(original == code)
    default: Issue.record("Wire error code lost")
    }
    #expect(rejection.details == Data("null".utf8))
  }
}
