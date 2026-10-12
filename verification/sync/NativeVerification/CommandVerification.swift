import Foundation
import NessaFeatures

private enum CommandCheckError: Error { case assertion(String) }
private func uuid() -> String { UUID().uuidString.lowercased() }
private func creation(_ id: String, agent: String? = nil, model: String? = nil)
  -> PreparedConversationCommand
{
  .create(.init(requestID: uuid(), conversationID: id, agent: agent, model: model))
}
private func submission(_ id: String) -> PreparedConversationCommand {
  .submit(
    .init(
      requestID: uuid(), conversationID: id, executionID: uuid(),
      text: "Synthetic command recovery check. Reply only OK. Do not use tools."))
}
enum CommandVerification {
  static func fixtures(_ endpoint: String) async throws {
    for operation in ["create", "submit"] {
      let mode = "journal-lost-" + operation
      let root = FileManager.default.temporaryDirectory.appendingPathComponent(uuid())
      defer { try? FileManager.default.removeItem(at: root) }
      let scope = PhoneCacheScope(address: endpoint, credential: "fixture-only", instance: mode)
      let journal = PhoneCommandJournal(store: PhoneCommandStore(root: root))
      let lease = try await journal.prepare(scope)
      let client = NessaGatewayClient()
      let connection = try await client.connectWithLease(
        address: endpoint, credential: "fixture-only", instance: mode)
      let id = uuid()
      if operation == "submit" {
        _ = try await client.dispatch(creation(id), connection: connection, scope: scope)
      }
      let intent = operation == "create" ? creation(id) : submission(id)
      do {
        _ = try await journal.execute(
          intent, lease: lease, connection: connection, transport: client)
        throw CommandCheckError.assertion("Lost acknowledgment unexpectedly returned")
      } catch let error as CommandCheckError { throw error } catch {
        guard ConnectionRecovery.retryable(error) else { throw error }
      }
      guard try await journal.pending(lease: lease) == [intent] else {
        throw CommandCheckError.assertion("Lost acknowledgment dropped identity")
      }
      let reopened = PhoneCommandJournal(store: PhoneCommandStore(root: root))
      let next = try await reopened.prepare(scope)
      let replacement = try await client.connectWithLease(
        address: endpoint, credential: "fixture-only", instance: mode)
      guard
        let confirmation = try await reopened.lookup(
          intent, lease: next, connection: replacement, transport: client)
      else {
        throw CommandCheckError.assertion("Durable receipt was not recovered")
      }
      _ = try await client.dispatch(intent, connection: replacement, scope: scope)
      let view = try await client.read(id)
      guard view.runtime?.agent == "creates-1",
        view.messages.count == (operation == "submit" ? 1 : 0)
      else {
        throw CommandCheckError.assertion("Exact retry duplicated an effect")
      }
      try await reopened.resolve(intent, acknowledgment: confirmation, lease: next)
      await client.disconnect()
      print(
        "PASS: lost \(operation) ACK survives disk recreation; receipt and exact retry have one effect"
      )
    }
    let client = NessaGatewayClient()
    let wrongScope = PhoneCacheScope(
      address: endpoint, credential: "fixture-only", instance: "journal-wrong")
    let connection = try await client.connectWithLease(
      address: endpoint, credential: "fixture-only", instance: "journal-wrong")
    let intent = creation(uuid())
    do {
      _ = try await client.dispatch(intent, connection: connection, scope: wrongScope)
      throw CommandCheckError.assertion("Foreign create acknowledgment accepted")
    } catch NessaGatewayError.invalidFrame {}
    do {
      _ = try await client.receipt(intent, connection: connection, scope: wrongScope)
      throw CommandCheckError.assertion("Foreign receipt identity accepted")
    } catch NessaGatewayError.invalidFrame {}
    let other = PhoneCacheScope(
      address: endpoint, credential: "fixture-only", instance: "journal-other")
    let next = try await client.connectWithLease(
      address: endpoint, credential: "fixture-only", instance: "journal-other")
    do {
      _ = try await client.dispatch(creation(uuid()), connection: next, scope: wrongScope)
      throw CommandCheckError.assertion("Old journal scope dispatched over replacement authority")
    } catch NessaGatewayError.disconnected {}
    let absent = try await client.receipt(creation(uuid()), connection: next, scope: other)
    guard !absent.found else {
      throw CommandCheckError.assertion("Unknown receipt invented progress")
    }
    await client.disconnect()
    print(
      "PASS: foreign ACK/receipt and cross-scope dispatch refused; absent receipt stays unresolved")
  }
  static func live(endpoint: String, credentialFile: String) async throws {
    let credential = try String(contentsOfFile: credentialFile, encoding: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let mode = "phone-command-experiment"
    let scope = PhoneCacheScope(address: endpoint, credential: credential, instance: mode)
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(uuid())
    defer { try? FileManager.default.removeItem(at: root) }
    let journal = PhoneCommandJournal(store: PhoneCommandStore(root: root))
    let lease = try await journal.prepare(scope)
    let client = NessaGatewayClient()
    let connection = try await client.connectWithLease(
      address: endpoint, credential: credential, instance: mode)
    let id = uuid()
    do {
      let create = creation(id, agent: "codex", model: "gpt-5.6-terra")
      _ = try await journal.execute(create, lease: lease, connection: connection, transport: client)
      _ = try await client.dispatch(create, connection: connection, scope: scope)
      let send = submission(id)
      try await journal.record(send, lease: lease)
      // The server accepted it; simulate the application losing that reply before resolution.
      _ = try await client.dispatch(send, connection: connection, scope: scope)
      let reopened = PhoneCommandJournal(store: PhoneCommandStore(root: root))
      let next = try await reopened.prepare(scope)
      guard
        let confirmation = try await reopened.lookup(
          send, lease: next, connection: connection, transport: client)
      else {
        throw CommandCheckError.assertion("Gateway did not retain the accepted command receipt")
      }
      _ = try await client.dispatch(send, connection: connection, scope: scope)
      let view = try await client.read(id)
      guard view.messages.count == 1,
        view.messages.first?.id
          == {
            if case .submit(let value) = send { return value.executionID }
            return ""
          }()
      else { throw CommandCheckError.assertion("Exact retry produced a duplicate turn") }
      try await reopened.resolve(send, acknowledgment: confirmation, lease: next)
      guard try await reopened.pending(lease: next).isEmpty else {
        throw CommandCheckError.assertion("Confirmed intent failed durable resolution")
      }
      try await client.delete(id)
      await client.disconnect()
      print(
        "PASS: real gateway create/send exact retries, disk recreation and receipt resolution; one turn; cleaned up"
      )
    } catch {
      try? await client.delete(id)
      await client.disconnect()
      throw error
    }
  }
}
