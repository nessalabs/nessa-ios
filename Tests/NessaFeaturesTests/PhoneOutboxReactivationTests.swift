import Foundation
import Testing
@testable import NessaFeatures

/// No sleeps: the first send is held after its departure has been persisted.
private actor ReactivationTransport: PhoneProductTransport, PhoneProductTransportFactory {
  private var entered = false
  private var waiting: CheckedContinuation<Void, Never>?
  private var answer: CheckedContinuation<PhoneSendAnswer, Never>?

  nonisolated func transport(for scope: PhoneCacheScope) -> any PhoneProductTransport { self }

  func send(_ intent: PhoneSendIntent) async -> PhoneSendAnswer {
    guard intent.commandID == "old-a" else { return .receipt(.queued) }
    return await withCheckedContinuation { continuation in
      answer = continuation
      entered = true
      waiting?.resume()
      waiting = nil
    }
  }

  func waitForOldSend() async {
    if entered { return }
    await withCheckedContinuation { waiting = $0 }
  }

  func failedBeforeSend() {
    entered = true
    waiting?.resume()
    waiting = nil
  }

  func finishOldSend() {
    answer?.resume(returning: .receipt(.queued))
    answer = nil
  }

  func lookup(_ intent: PhoneSendIntent) async -> PhoneLookupAnswer { .notFound }
  func uploadPhoneAttachment(_ attachment: DraftAttachment, conversationID: String) async throws
    -> NessaStoredAttachment
  { throw PhoneOutboxFailure.invalid }
  func phoneStop(conversationID: String, requestID: String, executionID: String) async
    -> PhoneSendAnswer
  { .broken }
  func phoneLookupStop(conversationID: String, requestID: String, executionID: String) async
    -> PhoneLookupAnswer
  { .broken }
}

@Test func lateSendSettlementPreservesCommandsWrittenAfterScopeReactivation() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let transport = ReactivationTransport()
  let chat = PhoneProductChat(root: root, transport: transport)
  let a = PhoneCacheScope(address: "a", credential: "a", instance: "phone")
  let b = PhoneCacheScope(address: "b", credential: "b", instance: "phone")
  let conversation = "00000000-0000-4000-8000-0000000000aa"
  await chat.activate(a)
  let oldSend = Task {
    do {
      return try await chat.deliver(text: "First", attachments: [], conversationID: conversation,
        identity: MessageCommandIdentity(requestID: "old-a", executionID: "old-turn"), scope: a)
    } catch {
      await transport.failedBeforeSend()
      throw error
    }
  }
  await transport.waitForOldSend()
  await chat.activate(b)
  await chat.activate(a)

  // Settle the replacement scope's send before releasing the old scope's response.
  // Always release the gate, including when the second send throws.
  let second: PhoneOutboxView
  do {
    second = try await chat.deliver(text: "Second", attachments: [], conversationID: conversation,
      identity: MessageCommandIdentity(requestID: "new-a", executionID: "new-turn"), scope: a)
  } catch {
    await transport.finishOldSend()
    _ = try? await oldSend.value
    throw error
  }
  #expect(second.outcome == .accepted)
  await transport.finishOldSend()
  _ = try await oldSend.value

  // The active store's cache can hide a lost disk row. Reopen to inspect durable state.
  let reopened = PhoneProductChat(root: root, transport: transport)
  await reopened.activate(a)
  let persisted = try await reopened.list(scope: a)
  #expect(Set(persisted.map(\.commandID)) == Set(["old-a", "new-a"]))
}

/// Delays only terminal persistence, after the gateway has already returned its receipt.
/// This models actor scheduling after transport drain, not a transport kept open across it.
private actor SettlementGateStore: PhoneOutboxStoring {
  let base: PhoneOutboxFileStore
  private var entered = false
  private var waiting: CheckedContinuation<Void, Never>?
  private var release: CheckedContinuation<Void, Never>?
  init(directory: URL) { base = PhoneOutboxFileStore(directory: directory) }
  func load(_ id: String) async throws -> PhoneOutboxRecord? { try await base.load(id) }
  func insert(_ record: PhoneOutboxRecord) async throws { try await base.insert(record) }
  func list() async throws -> [PhoneOutboxRecord] { try await base.list() }
  func replaceAndInsert(previous: PhoneOutboxRecord, next: PhoneOutboxRecord,
    draft: PhoneOutboxRecord) async throws
  { try await base.replaceAndInsert(previous: previous, next: next, draft: draft) }
  func replace(_ previous: PhoneOutboxRecord, with next: PhoneOutboxRecord) async throws {
    if next.outcome == .accepted {
      await withCheckedContinuation { continuation in
        release = continuation
        entered = true
        waiting?.resume()
        waiting = nil
      }
    }
    try await base.replace(previous, with: next)
  }
  func waitForSettlement() async {
    if entered { return }
    await withCheckedContinuation { waiting = $0 }
  }
  func failedBeforeSettlement() {
    entered = true
    waiting?.resume()
    waiting = nil
  }
  func finishSettlement() { release?.resume(); release = nil }
}

private struct ImmediateReceipt: PhoneOutboxAsking {
  func send(_ intent: PhoneSendIntent) async -> PhoneSendAnswer { .receipt(.queued) }
  func lookup(_ intent: PhoneSendIntent) async -> PhoneLookupAnswer { .notFound }
}

@Test func settlementAfterTransportReturnsPreservesReplacementOwnersRows() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: directory) }
  let oldStore = SettlementGateStore(directory: directory)
  let oldOutbox = PhoneOutbox(store: oldStore, gateway: ImmediateReceipt())
  let first = try PhoneSendIntent(conversationID: "00000000-0000-4000-8000-0000000000aa",
    commandID: "first", turnID: "first-turn", text: "First", images: [])
  _ = try await oldOutbox.hold(first)
  let settlement = Task {
    do { return try await oldOutbox.send(first.commandID) }
    catch { await oldStore.failedBeforeSettlement(); throw error }
  }
  await oldStore.waitForSettlement()
  // Transport is already finished. A new scope incarnation opens the same file.
  let newOutbox = PhoneOutbox(store: PhoneOutboxFileStore(directory: directory), gateway: ImmediateReceipt())
  let second = try PhoneSendIntent(conversationID: first.conversationID,
    commandID: "second", turnID: "second-turn", text: "Second", images: [])
  do {
    _ = try await newOutbox.hold(second)
    _ = try await newOutbox.send(second.commandID)
  } catch {
    await oldStore.finishSettlement()
    _ = try? await settlement.value
    throw error
  }
  await oldStore.finishSettlement()
  _ = try await settlement.value
  let fresh = PhoneOutboxFileStore(directory: directory)
  #expect(Set(try await fresh.list().map { $0.intent.commandID }) == Set(["first", "second"]))
}
