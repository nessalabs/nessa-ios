import Foundation
import NessaFeatures

private enum PairingCheckError: Error { case failed(String) }
private func pairingCheck(_ condition: Bool, _ message: String) throws {
  guard condition else { throw PairingCheckError.failed(message) }
}
private func connectPairing(_ client: NessaGatewayClient, endpoint: String, mode: String)
  async throws -> GatewayConnectionLease
{
  try await client.connectWithLease(address: endpoint, credential: "fixture-only", instance: mode)
}
private func pairingMarker(_ root: String, _ name: String) -> URL {
  URL(fileURLWithPath: root).appendingPathComponent(name)
}
private func awaitPairingMarker(_ root: String, _ name: String) async throws {
  for _ in 0..<500 {
    if FileManager.default.fileExists(atPath: pairingMarker(root, name).path) { return }
    try await Task.sleep(for: .milliseconds(10))
  }
  throw PairingCheckError.failed("No admitted request marker: " + name)
}
private func checkFullPairingStatus(_ value: GatewayPairingStatus) throws {
  try pairingCheck(
    value.invitationID == Data(0..<16) && value.consentID == Data(16..<32), "Exact identities")
  try pairingCheck(
    value.generation == UInt64.max && value.createdAtMs == 9_007_199_254_740_993
      && value.expiresAtMs == UInt64.max, "Exact large integers")
  try pairingCheck(
    value.consentClass == "gateway-conversation-read" && value.grant.action == "conversation.read"
      && value.grant.resource == .init(organizationID: "org", id: "gateway"), "Consent and grant")
  try pairingCheck(
    value.phase == .terminal && value.cleanupPending && value.claimedDeviceKey == Data(0..<32)
      && value.credentialID == "device-credential", "Independent terminal/staged fields")
  try pairingCheck(
    value.receiver == .init(id: "receiver", accessEpoch: UInt64.max)
      && value.terminal == .init(cause: .cancelled, initiator: .device(Data(0..<32))),
    "Receiver and terminal")
}

enum PairingVerification {
  static func run(endpoint: String, markers: String) async throws {
    try await verifyPairingSubstitution()
    let client = NessaGatewayClient()
    let lease = try await connectPairing(client, endpoint: endpoint, mode: "complete")
    let source = try await client.authenticatedSession(for: lease)
    let created = try await client.createDevice(on: lease)
    try pairingCheck(
      created.source == source && created.value.code == "ABCD-EFGH",
      "Create receipt original source/code")
    try checkFullPairingStatus(created.value.status)
    let status = try await client.pairingStatus(Data(0..<16), on: lease)
    try pairingCheck(status.source == source, "Status source")
    try checkFullPairingStatus(status.value)
    let approval = try await client.approvePairing(Data(0..<16), deviceKey: Data(0..<32), on: lease)
    try pairingCheck(
      approval.source == source && approval.value.activationStopped == .retryable,
      "Committed approval and stopped activation")
    try checkFullPairingStatus(approval.value.status)
    let cancelled = try await client.cancelPairing(Data(0..<16), on: lease)
    try pairingCheck(cancelled.source == source, "Cancel source")
    try checkFullPairingStatus(cancelled.value)
    let pending = try await client.pendingPairings(on: lease)
    try pairingCheck(pending.source == source && pending.value.count == 1, "Pending source/list")
    try checkFullPairingStatus(pending.value[0])
    let replacement = try await connectPairing(client, endpoint: endpoint, mode: "replacement")
    try pairingCheck(
      created.source == source && replacement != source.connection,
      "Accepted old receipt survives replacement")
    do {
      _ = try await client.createDevice(on: lease)
      throw PairingCheckError.failed("Stale lease dispatched")
    } catch NessaGatewayError.disconnected {}
    try pairingCheck(
      !FileManager.default.fileExists(atPath: pairingMarker(markers, "replacement.request").path),
      "No replacement pairing effect")
    let admissionGate = PairingAdmissionGate()
    let cancelledBefore = Task {
      await admissionGate.wait()
      return try await client.createDevice(on: replacement)
    }
    cancelledBefore.cancel()
    await admissionGate.release()
    do {
      _ = try await cancelledBefore.value
      throw PairingCheckError.failed("Pre-admission cancellation dispatched")
    } catch is CancellationError {}
    // Invalid input remains unadmitted; no source-bearing operation failure.
    do {
      _ = try await client.approvePairing(Data(0..<15), deviceKey: Data(0..<32), on: replacement)
      throw PairingCheckError.failed("Invalid input dispatched")
    } catch is GatewayPairingOperationFailure {
      throw PairingCheckError.failed("Invalid input marked admitted")
    } catch is PairingCheckError {
      throw PairingCheckError.failed("Invalid input dispatched")
    } catch {}
    for mode in [
      "bad-ok", "missing-ok", "missing-payload", "contradiction", "missing-code", "null-option",
      "zero-generation", "overflow", "fraction", "bool-byte", "malformed-json", "missing-id",
      "empty-id", "wrong-kind",
    ] {
      let current = try await connectPairing(client, endpoint: endpoint, mode: mode)
      let expected = try await client.authenticatedSession(for: current)
      do {
        _ = try await client.pairingStatus(Data(0..<16), on: current)
        throw PairingCheckError.failed("Malformed frame accepted: " + mode)
      } catch let failure as GatewayPairingOperationFailure {
        guard case NessaGatewayError.invalidFrame = failure.underlying else {
          throw PairingCheckError.failed(
            "Grammar is not the application invalid-frame failure: " + mode)
        }
        try pairingCheck(failure.source == expected, "Grammar failure original admission")
      }
    }
    let codes =
      GatewayPairingKnownError.allCasesForVerification + [
        "forbidden", "invalid_request", "unknown_method", "future_error",
      ]
    for code in codes {
      let current = try await connectPairing(client, endpoint: endpoint, mode: "error-" + code)
      let expected = try await client.authenticatedSession(for: current)
      do {
        _ = try await client.createDevice(on: current)
        throw PairingCheckError.failed("Refusal accepted")
      } catch let failure as GatewayPairingOperationFailure {
        guard let rejection = failure.underlying as? GatewayPairingRejection else {
          throw PairingCheckError.failed("Code lost")
        }
        try pairingCheck(
          failure.source == expected && rejection.code == code
            && rejection.diagnostic.contains("not authority"), "Original typed refusal")
        guard let details = rejection.details,
          let object = try JSONSerialization.jsonObject(with: details) as? [String: Any],
          let ordinal = object["ordinal"] as? NSNumber
        else { throw PairingCheckError.failed("Details lost") }
        try pairingCheck(ordinal.stringValue == "18446744073709551615", "Exact rejection details")
        if let known = GatewayPairingKnownError(rawValue: code) {
          guard case .known(let actual) = rejection.kind, actual == known else {
            throw PairingCheckError.failed("Known kind lost")
          }
        } else if code == "future_error" {
          guard case .unknown(let original) = rejection.kind, original == code else {
            throw PairingCheckError.failed("Unknown code invented terminal behavior")
          }
        }
      }
    }
    let admitted = try await connectPairing(client, endpoint: endpoint, mode: "delay-cancelled")
    let admittedSource = try await client.authenticatedSession(for: admitted)
    let operation = Task { try await client.createDevice(on: admitted) }
    try await awaitPairingMarker(markers, "delay-cancelled.request")
    operation.cancel()
    try Data().write(to: pairingMarker(markers, "delay-cancelled.release"))
    let historical = try await operation.value
    try pairingCheck(
      historical.source == admittedSource && historical.value.code == "ABCD-EFGH",
      "Admitted cancellation preserves committed code/receipt")
    let old = try await connectPairing(client, endpoint: endpoint, mode: "delay-replaced")
    let oldSource = try await client.authenticatedSession(for: old)
    let lost = Task { try await client.createDevice(on: old) }
    try await awaitPairingMarker(markers, "delay-replaced.request")
    _ = try await connectPairing(client, endpoint: endpoint, mode: "last")
    do {
      _ = try await lost.value
      throw PairingCheckError.failed("Lost request claimed success")
    } catch let failure as GatewayPairingOperationFailure {
      try pairingCheck(
        failure.source == oldSource, "Unknown admitted result retains original source")
    }
    try Data().write(to: pairingMarker(markers, "delay-replaced.release"))
    try pairingCheck(
      !FileManager.default.fileExists(atPath: pairingMarker(markers, "last.request").path),
      "No implicit create retry")
    await client.disconnect()
    print(
      "PASS: actual pairing WebSocket methods, complete UInt64/byte DTOs, strict frames, typed refusals, cancellation and replacement ownership"
    )
  }
}
extension GatewayPairingKnownError {
  fileprivate static let allCasesForVerification = [
    "pairing_not_configured", "pairing_not_found", "pairing_slot_occupied", "pairing_capacity",
    "pairing_conflict", "pairing_ineligible", "pairing_busy", "pairing_unavailable",
  ]
}

private actor PairingAdmissionGate {
  private var released = false
  private var waiter: CheckedContinuation<Void, Never>?
  func wait() async {
    if released { return }
    await withCheckedContinuation { waiter = $0 }
  }
  func release() {
    released = true
    waiter?.resume()
    waiter = nil
  }
}

extension PairingVerification {
  static func live(endpoint: String, credentialFile: String) async throws {
    let credential = try String(contentsOfFile: credentialFile, encoding: .utf8).trimmingCharacters(
      in: .whitespacesAndNewlines)
    let client = NessaGatewayClient()
    let lease = try await client.connectWithLease(
      address: endpoint, credential: credential, instance: "ios-pairing-read-only-check")
    let source = try await client.authenticatedSession(for: lease)
    do {
      let result = try await client.pendingPairings(on: lease)
      guard result.source == source else {
        throw PairingCheckError.failed("Real pairing publication source changed")
      }
      print(
        "PASS: real gateway pending pairing read; no create/approval or credential changes; items=\(result.value.count)"
      )
    } catch let failure as GatewayPairingOperationFailure {
      guard failure.source == source, let rejection = failure.underlying as? GatewayPairingRejection
      else { throw failure }
      print(
        "OBSERVED: real gateway pairing.pending refusal code=\(rejection.code); no capability or credential changes"
      )
    }
    await client.disconnect()
  }
}
