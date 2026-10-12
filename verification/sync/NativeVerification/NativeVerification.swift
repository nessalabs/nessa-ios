import Foundation
import NessaFeatures

private let a = "00000000-0000-4000-8000-000000000001"
private let b = "00000000-0000-4000-8000-000000000002"
private let c = "00000000-0000-4000-8000-000000000003"
private enum Failure: Error { case assertion(String) }
private func say(_ message: String) { FileHandle.standardOutput.write(Data((message + "\n").utf8)) }

private func registrationHandoff(_ endpoint: String, rapid: Bool) async throws {
  let client = NessaGatewayClient()
  try await client.connect(
    address: endpoint, credential: "fixture-only", instance: rapid ? "rapid" : "handoff")
  let inbox = try await client.follow(nil)
  guard case .list = try await firstPublication(inbox) else {
    throw Failure.assertion("Missing initial inbox")
  }
  let old = Task { try await client.follow(a) }
  try await Task.sleep(for: .milliseconds(80))
  old.cancel()
  let next = Task { try await client.follow(b) }
  let stream: AsyncThrowingStream<ConversationUpdate, Error>
  if rapid {
    try await Task.sleep(for: .milliseconds(50))
    stream = try await client.follow(c)
    do {
      _ = try await next.value
      throw Failure.assertion("Obsolete navigation registered")
    } catch is CancellationError {}
  } else {
    stream = try await next.value
  }
  guard case .view(_, let view) = try await firstPublication(stream),
    view.conversationId == (rapid ? c : b)
  else { throw Failure.assertion("Replacement failed before old registration settled") }
  do {
    _ = try await old.value
    throw Failure.assertion("Canceled registration returned")
  } catch is CancellationError {}
  await client.disconnect()
  say("PASS: \(rapid ? "rapid A→B→C latest navigation" : "cancel-before-ack handoff with inbox")")
}
private func asynchronousActiveCleanup(_ endpoint: String) async throws {
  let client = NessaGatewayClient()
  try await client.connect(address: endpoint, credential: "fixture-only", instance: "active")
  let stream = try await client.follow(a)
  let consumer = Task { do { for try await _ in stream {} } catch {} }
  try await Task.sleep(for: .milliseconds(30))
  consumer.cancel()
  await consumer.value
  let next = try await client.follow(b)
  guard case .view(_, let view) = try await firstPublication(next), view.conversationId == b else {
    throw Failure.assertion("New navigation overtook delayed asynchronous cleanup")
  }
  await client.disconnect()
  say("PASS: asynchronous cancellation waits for delayed unsubscribe acknowledgement")
}
private func rejectedForeignPublication(_ endpoint: String) async throws {
  let client = NessaGatewayClient()
  try await client.connect(address: endpoint, credential: "fixture-only", instance: "foreign")
  let stream = try await client.follow(a)
  do {
    _ = try await firstPublication(stream)
    throw Failure.assertion("Foreign view delivered")
  } catch NessaGatewayError.invalidFrame {}
  await client.disconnect()
  say("PASS: foreign conversation publication refused")
}
private func lostRegistration(_ endpoint: String) async throws {
  let client = NessaGatewayClient()
  try await client.connect(address: endpoint, credential: "fixture-only", instance: "lost")
  let inbox = try await client.follow(nil)
  _ = try await firstPublication(inbox)
  do {
    _ = try await client.follow(a)
    throw Failure.assertion("Lost registration succeeded")
  } catch NessaGatewayError.timeout {}
  do {
    _ = try await firstPublication(inbox)
    throw Failure.assertion("Leaked inbox after lost registration")
  } catch NessaGatewayError.disconnected {}
  do {
    _ = try await client.list()
    throw Failure.assertion("Socket owner survived unknown subscription")
  } catch NessaGatewayError.disconnected {}
  say("PASS: lost registration closes unknown watcher owner and all feeds")
}
private func missingPublication(_ endpoint: String) async throws {
  let client = NessaGatewayClient()
  try await client.connect(address: endpoint, credential: "fixture-only", instance: "missing")
  let stream = try await client.follow(b)
  do {
    _ = try await firstPublication(stream, within: .milliseconds(100))
    throw Failure.assertion("Missing publication was accepted")
  } catch NessaGatewayError.timeout {}
  await client.disconnect()
  say("PASS: acknowledged subscription with missing publication hits its deadline")
}
private func connectionOwnership(_ endpoint: String) async throws {
  let client = NessaGatewayClient()
  let old = try await client.connectWithLease(
    address: endpoint, credential: "fixture-only", instance: "lease")
  let replacement = try await client.connectWithLease(
    address: endpoint, credential: "fixture-only", instance: "lease")
  await client.retire(old)
  let inbox = try await client.follow(nil)
  guard case .list = try await firstPublication(inbox) else {
    throw Failure.assertion("Old cleanup retired the replacement connection")
  }
  await client.retire(replacement)
  do {
    _ = try await client.list()
    throw Failure.assertion("Current connection lease failed to retire its socket")
  } catch NessaGatewayError.disconnected {}
  say("PASS: old connection cleanup leaves replacement usable; current lease retires it")
}
@main struct NativeVerification {
  static func main() async {
    do {
      if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--image" {
        try await ImageVerification.run(
          endpoint: CommandLine.arguments[2], credentialFile: CommandLine.arguments[3])
        return
      }
      if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--live" {
        try await LiveVerification.run(
          endpoint: CommandLine.arguments[2], credentialFile: CommandLine.arguments[3])
        return
      }
      guard CommandLine.arguments.count == 2 else {
        throw Failure.assertion("Expected fixture endpoint")
      }
      let endpoint = CommandLine.arguments[1]
      try await registrationHandoff(endpoint, rapid: false)
      try await registrationHandoff(endpoint, rapid: true)
      try await asynchronousActiveCleanup(endpoint)
      try await rejectedForeignPublication(endpoint)
      try await missingPublication(endpoint)
      try await connectionOwnership(endpoint)
      try await lostRegistration(endpoint)
    } catch {
      say("FAIL: \(error)")
      exit(1)
    }
  }
}
