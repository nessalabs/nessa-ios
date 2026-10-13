import Foundation
import Testing

@testable import NessaFeatures

private actor PairingSettlementGate {
  private var settled = false
  private var waiter: CheckedContinuation<Void, Never>?
  func holdAcceptedReceipt() async {
    settled = true
    await withCheckedContinuation { waiter = $0 }
  }
  func accepted() -> Bool { settled }
  func release() {
    waiter?.resume()
    waiter = nil
  }
}

@Test(
  .enabled(if: ProcessInfo.processInfo.environment["NESSA_PAIRING_FIXTURE_ENDPOINT"] != nil),
  arguments: [false, true])
func pairingReceiptAfterActorSettlementSurvivesReplacementAndCancellation(cancel: Bool) async throws
{
  let endpoint = ProcessInfo.processInfo.environment["NESSA_PAIRING_FIXTURE_ENDPOINT"]!
  let gate = PairingSettlementGate()
  let client = NessaGatewayClient(pairingAccepted: { await gate.holdAcceptedReceipt() })
  let lease = try await client.connectWithLease(
    address: endpoint, credential: "fixture-only",
    instance: cancel ? "settled-cancel" : "settled-replace")
  let source = try await client.authenticatedSession(for: lease)
  let request = Task { try await client.createDevice(on: lease) }
  for _ in 0..<500 {
    if await gate.accepted() { break }
    try await Task.sleep(for: .milliseconds(10))
  }
  guard await gate.accepted() else {
    await client.disconnect()
    Issue.record("Receipt did not settle")
    return
  }
  if cancel { request.cancel() }
  let replacement = try await client.connectWithLease(
    address: endpoint, credential: "fixture-only", instance: "after-settlement")
  #expect(replacement != source.connection)
  await gate.release()
  let receipt = try await request.value
  #expect(receipt.source == source)
  #expect(receipt.value.code == "ABCD-EFGH")
  #expect(receipt.value.status.generation == UInt64.max)
  await client.disconnect()
}
