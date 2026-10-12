import Foundation
import NessaFeatures

private actor Samples {
  let clock = ContinuousClock()
  var seen: [String: (first: ContinuousClock.Instant, complete: ContinuousClock.Instant?)] = [:]
  var initial = false
  var lists = 0
  func view(_ view: NessaConversationView) {
    initial = true
    for message in view.messages {
      let first = seen[message.id]?.first ?? clock.now
      seen[message.id] = (
        first, message.status == "completed" ? clock.now : seen[message.id]?.complete
      )
    }
  }
  func list() { lists += 1 }
  func result(_ id: String) -> (ContinuousClock.Instant, ContinuousClock.Instant?)? {
    seen[id].map { ($0.first, $0.complete) }
  }
}
private func ms(_ duration: Duration) -> Double {
  Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
}
enum LiveVerification {
  static func run(endpoint: String, credentialFile: String) async throws {
    let credential = try String(contentsOfFile: credentialFile, encoding: .utf8).trimmingCharacters(
      in: .whitespacesAndNewlines)
    let client = NessaGatewayClient()
    let clock = ContinuousClock()
    let start = clock.now
    try await client.connect(
      address: endpoint, credential: credential, instance: "phone-sync-experiment")
    print("AUTH_MS: \(ms(start.duration(to: clock.now)))")
    let samples = Samples()
    let inbox = try await client.follow(nil)
    let inboxTask = Task { do { for try await _ in inbox { await samples.list() } } catch {} }
    var createdID: String?
    do {
      let createStart = clock.now
      let id = try await client.create(agent: "codex", model: "gpt-5.6-terra")
      createdID = id
      print("CREATE_MS: \(ms(createStart.duration(to: clock.now)))")
      let stream = try await client.follow(id)
      let viewsTask = Task {
        do {
          for try await update in stream {
            if case .view(_, let view) = update { await samples.view(view) }
          }
        } catch {}
      }
      for _ in 0..<500 {
        if await samples.initial { break }
        try await Task.sleep(for: .milliseconds(10))
      }
      guard await samples.initial else { throw NessaGatewayError.timeout }
      print("PASS: initial conversation frame delivered without polling")
      for index in 1...5 {
        let sent = clock.now
        let receipt = try await client.send(
          "Sync timing probe \(index). Reply with only OK. Do not use tools.", conversationID: id)
        let acknowledged = clock.now
        var completed = false
        for _ in 0..<3000 {
          if let (visible, complete) = await samples.result(receipt), let complete {
            print(
              "SAMPLE \(index): ACK_MS=\(ms(sent.duration(to: acknowledged))) FIRST_VIEW_MS=\(ms(sent.duration(to: visible))) COMPLETE_MS=\(ms(sent.duration(to: complete)))"
            )
            completed = true
            break
          }
          try await Task.sleep(for: .milliseconds(10))
        }
        guard completed else { throw NessaGatewayError.timeout }
      }
      viewsTask.cancel()
      await viewsTask.value
      // Deliberately resubscribe immediately after cancellation.
      let replacement = try await client.follow(id)
      guard case .view = try await firstPublication(replacement, within: .seconds(10)) else {
        throw NessaGatewayError.invalidFrame
      }
      print("PASS: immediate resubscription after cancellation")
      print("LIST_EVENTS: \(await samples.lists)")
      inboxTask.cancel()
      await inboxTask.value
      try await client.delete(id)
      await client.disconnect()
      print("PASS: disposable conversation cleaned up")
    } catch {
      inboxTask.cancel()
      await inboxTask.value
      if let id = createdID { try? await client.delete(id) }
      await client.disconnect()
      throw error
    }
  }
}
