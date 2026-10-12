import Foundation
import NessaFeatures

enum IdentityVerification {
  private enum Failure: Error { case assertion(String) }
  static func live(endpoint: String, credentialFile: String) async throws {
    let credential = try String(contentsOfFile: credentialFile, encoding: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let client = NessaGatewayClient()
    let lease = try await client.connectWithLease(
      address: endpoint, credential: credential, instance: "phone-identity-verification")
    do {
      let publication = try await client.authenticatedSession(for: lease)
      guard publication.connection == lease else {
        throw Failure.assertion("Foreign identity lease")
      }
      print("PASS: real gateway complete authenticated identity/restrictions captured")
      await client.retire(lease)
      do {
        _ = try await client.authenticatedSession(for: lease)
        throw Failure.assertion("Real retired connection retained identity")
      } catch NessaGatewayError.disconnected {}
      print("PASS: real gateway retirement fences identity")
    } catch {
      await client.disconnect()
      throw error
    }
  }
  private static func waitForEntry(_ marker: URL) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while !FileManager.default.fileExists(atPath: marker.path) {
      guard ContinuousClock.now < deadline else {
        throw Failure.assertion("Authentication never entered")
      }
      try await Task.sleep(for: .milliseconds(10))
    }
  }
  static func run(endpoint: String, markers: String) async throws {
    try await verifyIdentitySubstitution()
    let racing = NessaGatewayClient()
    for batch in 0..<10 {
      await withTaskGroup(of: Void.self) { group in
        for index in 0..<10 {
          group.addTask {
            _ = try? await racing.connectWithLease(
              address: endpoint, credential: "fixture-only",
              instance: "challenge-overlap-\(batch)-\(index)")
          }
        }
      }
    }
    let final = try await racing.connectWithLease(
      address: endpoint, credential: "fixture-only", instance: "challenge-overlap-final")
    _ = try await racing.authenticatedSession(for: final)
    guard
      !FileManager.default.fileExists(
        atPath: URL(fileURLWithPath: markers).appendingPathComponent("foreign-challenge").path)
    else { throw Failure.assertion("Old challenge authenticated a different socket") }
    await racing.disconnect()
    print(
      "PASS: 100 overlapping dials never reuse another socket's challenge; final connection authenticates"
    )
    for suffix in ["success", "refusal", "disconnect"] {
      let client = NessaGatewayClient()
      let mode = "auth-delay-" + suffix + "-" + UUID().uuidString
      let old = Task {
        try await client.connectWithLease(
          address: endpoint, credential: "fixture-only", instance: mode)
      }
      try await waitForEntry(URL(fileURLWithPath: markers).appendingPathComponent(mode))
      let replacement: GatewayConnectionLease?
      if suffix == "disconnect" {
        await client.disconnect()
        replacement = nil
      } else {
        replacement = try await client.connectWithLease(
          address: endpoint, credential: "fixture-only", instance: "identity-replacement")
      }
      do {
        _ = try await old.value
        throw Failure.assertion("Obsolete authentication succeeded")
      } catch let error as Failure { throw error } catch {}
      // Wait past the peer's bounded late response/failure, then verify ownership.
      try await Task.sleep(for: .milliseconds(400))
      if let replacement {
        let publication = try await client.authenticatedSession(for: replacement)
        guard publication.connection == replacement,
          publication.snapshot.identity.principalID == "owner-identity-replacement"
        else { throw Failure.assertion("Old authentication replaced current identity") }
      } else {
        do {
          _ = try await client.authenticatedSession(for: GatewayConnectionLease())
          throw Failure.assertion("Disconnected authentication left an identity")
        } catch NessaGatewayError.disconnected {}
      }
      await client.disconnect()
    }
    let client = NessaGatewayClient()
    do {
      _ = try await client.connectWithLease(
        address: endpoint, credential: "fixture-only", instance: "identity-incomplete")
      throw Failure.assertion("Missing authenticated identity was accepted")
    } catch let error as Failure { throw error } catch {}
    let lease = try await client.connectWithLease(
      address: endpoint, credential: "fixture-only", instance: "identity-drop")
    let deadline = ContinuousClock.now.advanced(by: .seconds(5))
    while true {
      do {
        _ = try await client.authenticatedSession(for: lease)
      } catch NessaGatewayError.disconnected { break }
      guard ContinuousClock.now < deadline else {
        throw Failure.assertion("Dead transport retained identity")
      }
      try await Task.sleep(for: .milliseconds(10))
    }
    await client.disconnect()
    print(
      "PASS: delayed authentication success/refusal/disconnect fence identity; current transport loss retires it"
    )
  }
}
