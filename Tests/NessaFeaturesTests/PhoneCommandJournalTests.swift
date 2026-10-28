import Darwin
import Foundation
import Testing

@testable import NessaFeatures

private func command(_ number: Int = 1, text: String = "Synthetic message")
  -> PreparedConversationCommand
{
  .submit(
    .init(
      requestID: String(format: "00000000-0000-4000-8000-%012x", number),
      conversationID: "00000000-0000-4000-8000-100000000001",
      executionID: String(format: "00000000-0000-4000-8000-%012x", number + 1000), text: text))
}
private func scope(_ credential: String = "fixture-only") -> PhoneCacheScope {
  PhoneCacheScope(address: "ws://127.0.0.1:1/session", credential: credential, instance: "journal")
}
private actor ControlledCommandStore: CommandJournalStoring {
  var values: [String: PhoneCommands] = [:]
  var writes = 0
  var failOn: Int?
  var blockOn: Int?
  private var gate: CheckedContinuation<Void, Never>?
  func fail(_ index: Int?) { failOn = index }
  func block(_ index: Int) { blockOn = index }
  func release() {
    gate?.resume()
    gate = nil
  }
  func load(_ scope: PhoneCacheScope) -> PhoneCommands? { values[scope.key] }
  func save(_ commands: PhoneCommands, scope: PhoneCacheScope, replacing expected: PhoneCommands?)
    async throws
  {
    writes += 1
    let index = writes
    if blockOn == index { await withCheckedContinuation { gate = $0 } }
    if failOn == index { throw PhoneCommandStoreError.unavailable }
    guard values[scope.key] == expected else { throw PhoneCommandStoreError.changed }
    values[scope.key] = commands
  }
}
private actor CommandTransport: PreparedCommandTransport {
  let store: ControlledCommandStore
  var dispatched: [PreparedConversationCommand] = []
  var persistedBeforeDispatch = true
  var loseACK = false
  var refusal: ConversationCommandRefusal.Reason?
  var offeredReceipt: ConversationCommandReceipt?
  init(store: ControlledCommandStore) { self.store = store }
  func dropACK(_ value: Bool) { loseACK = value }
  func refuse(_ value: ConversationCommandRefusal.Reason?) { refusal = value }
  func offer(_ receipt: ConversationCommandReceipt) { offeredReceipt = receipt }
  func dispatch(
    _ command: PreparedConversationCommand, connection: GatewayConnectionLease,
    scope: PhoneCacheScope
  ) async throws -> ConversationCommandAcknowledgment {
    if await store.load(scope)?.commands.contains(command) != true {
      persistedBeforeDispatch = false
    }
    dispatched.append(command)
    if let refusal { throw ConversationCommandRefusal(command: command, reason: refusal) }
    if loseACK { throw NessaGatewayError.timeout }
    switch command {
    case .create(let value): return .created(value.conversationID)
    case .submit(let value): return .submitted(value.executionID)
    }
  }
  func receipt(
    _ command: PreparedConversationCommand, connection: GatewayConnectionLease,
    scope: PhoneCacheScope
  ) -> ConversationCommandReceipt {
    offeredReceipt ?? .init(found: false, requestId: command.requestID)
  }
}
private func entered(_ condition: @Sendable () async -> Bool) async throws {
  // This is a scheduling wait for the blocked store write, not a product
  // latency budget. Parallel Swift tests may delay the task on a CI runner.
  let end = ContinuousClock.now + .seconds(15)
  while ContinuousClock.now < end {
    if await condition() { return }
    try await Task.sleep(for: .milliseconds(1))
  }
  #expect(await condition())
}
@Test func journalPersistsBeforeDispatchAndLostACKRetainsExactRetryIdentity() async throws {
  let store = ControlledCommandStore()
  let transport = CommandTransport(store: store)
  let journal = PhoneCommandJournal(store: store)
  let lease = try await journal.prepare(scope())
  await transport.dropACK(true)
  await #expect(throws: NessaGatewayError.self) {
    try await journal.execute(
      command(), lease: lease, connection: GatewayConnectionLease(), transport: transport)
  }
  #expect(try await journal.pending(lease: lease) == [command()])
  let reopened = PhoneCommandJournal(store: store)
  let next = try await reopened.prepare(scope())
  await transport.dropACK(false)
  _ = try await reopened.execute(
    command(), lease: next, connection: GatewayConnectionLease(), transport: transport)
  #expect(await transport.dispatched == [command(), command()])
  #expect(await transport.persistedBeforeDispatch)
  #expect(try await reopened.pending(lease: next).isEmpty)
  #expect(await store.load(scope())?.commands.isEmpty == true)
}
@Test func cancellationAfterPersistenceDoesNotDispatchOrRemoveIntent() async throws {
  let store = ControlledCommandStore()
  await store.block(1)
  let transport = CommandTransport(store: store)
  let journal = PhoneCommandJournal(store: store)
  let lease = try await journal.prepare(scope())
  let sending = Task {
    try await journal.execute(
      command(), lease: lease, connection: GatewayConnectionLease(), transport: transport)
  }
  try await entered { await store.writes == 1 }
  sending.cancel()
  await store.release()
  await #expect(throws: CancellationError.self) { try await sending.value }
  #expect(await transport.dispatched.isEmpty)
  #expect(try await journal.pending(lease: lease) == [command()])
  #expect(await store.load(scope())?.commands == [command()])
}
@Test func saveFailureBlocksDispatchAndResolutionFailurePreservesPendingIntent() async throws {
  let store = ControlledCommandStore()
  await store.fail(1)
  let transport = CommandTransport(store: store)
  let journal = PhoneCommandJournal(store: store)
  let lease = try await journal.prepare(scope())
  await #expect(throws: PhoneCommandStoreError.unavailable) {
    try await journal.execute(
      command(), lease: lease, connection: GatewayConnectionLease(), transport: transport)
  }
  #expect(await transport.dispatched.isEmpty)
  await store.fail(4)
  await #expect(throws: PhoneCommandStoreError.unavailable) {
    try await journal.execute(
      command(), lease: lease, connection: GatewayConnectionLease(), transport: transport)
  }
  #expect(await transport.dispatched == [command()])
  #expect(try await journal.pending(lease: lease) == [command()])
  #expect(await store.load(scope())?.commands == [command()])
  await store.fail(nil)
  try await journal.resolve(
    command(), acknowledgment: .submitted("00000000-0000-4000-8000-0000000003e9"), lease: lease)
  #expect(try await journal.pending(lease: lease).isEmpty)
}
@Test func uncertainReceiptsDoNotResolveAndWrongIdentityOrPayloadIsRefused() async throws {
  let store = ControlledCommandStore()
  let journal = PhoneCommandJournal(store: store)
  let lease = try await journal.prepare(scope())
  try await journal.record(command(), lease: lease)
  await #expect(throws: ConversationCommandError.conflict) {
    try await journal.record(command(text: "Different payload"), lease: lease)
  }
  let transport = CommandTransport(store: store)
  #expect(
    try await journal.lookup(
      command(), lease: lease, connection: GatewayConnectionLease(), transport: transport) == nil)
  await transport.offer(.init(found: true, requestId: command().requestID, stage: .attempted))
  #expect(
    try await journal.lookup(
      command(), lease: lease, connection: GatewayConnectionLease(), transport: transport) == nil)
  await transport.offer(
    .init(found: true, requestId: command(2).requestID, stage: .settled, outcome: .dispatched))
  await #expect(throws: ConversationCommandError.invalid) {
    try await journal.lookup(
      command(), lease: lease, connection: GatewayConnectionLease(), transport: transport)
  }
  await #expect(throws: ConversationCommandError.conflict) {
    try await journal.resolve(
      command(), acknowledgment: .created(command().conversationID), lease: lease)
  }
  #expect(try await journal.pending(lease: lease) == [command()])
}
@Test func concurrentRecordsPublishOwnedWriteBeforeNextMutation() async throws {
  let store = ControlledCommandStore()
  await store.block(1)
  let journal = PhoneCommandJournal(store: store)
  let lease = try await journal.prepare(scope())
  let first = Task { try await journal.record(command(1), lease: lease) }
  try await entered { await store.writes == 1 }
  let second = Task { try await journal.record(command(2), lease: lease) }
  await store.release()
  try await first.value
  try await second.value
  #expect(try await journal.pending(lease: lease) == [command(1), command(2)])
  #expect(await store.load(scope())?.commands == [command(1), command(2)])
}

@Test func productAdmissionSerializesConcurrentIntentsAndAllowsOnlyExactRetry() async throws {
  let store = ControlledCommandStore()
  await store.block(1)
  let journal = PhoneCommandJournal(store: store)
  let lease = try await journal.prepare(scope())
  let first = Task { try await journal.recordProductIntent(command(1), lease: lease) }
  try await entered { await store.writes == 1 }
  let second = Task { try await journal.recordProductIntent(command(2), lease: lease) }
  await store.release()
  try await first.value
  await #expect(throws: CommandAdmissionBlocked.self) { try await second.value }
  try await journal.recordProductIntent(command(1), lease: lease)
  #expect(await store.writes == 1)
  await #expect(throws: ConversationCommandError.conflict) {
    try await journal.recordProductIntent(command(1, text: "Changed retry"), lease: lease)
  }
  let other = PreparedConversationCommand.submit(
    .init(
      requestID: "00000000-0000-4000-8000-000000000010",
      conversationID: "00000000-0000-4000-8000-100000000002",
      executionID: "00000000-0000-4000-8000-000000000011", text: "Different chat"))
  try await journal.recordProductIntent(other, lease: lease)
  #expect(try await journal.pending(lease: lease) == [command(1), other])
}

@Test func unresolvedCreationBlocksAnotherCreationButNotAnExistingChatSend() async throws {
  let journal = PhoneCommandJournal(store: InMemoryCommandJournalStore())
  let lease = try await journal.prepare(scope())
  let first = PreparedConversationCommand.create(
    .init(
      requestID: "00000000-0000-4000-8000-000000000010",
      conversationID: "00000000-0000-4000-8000-100000000010", agent: nil, model: nil))
  let second = PreparedConversationCommand.create(
    .init(
      requestID: "00000000-0000-4000-8000-000000000011",
      conversationID: "00000000-0000-4000-8000-100000000011", agent: nil, model: nil))
  try await journal.recordProductIntent(first, lease: lease)
  await #expect(throws: CommandAdmissionBlocked.self) {
    try await journal.recordProductIntent(second, lease: lease)
  }
  try await journal.recordProductIntent(command(), lease: lease)
  #expect(try await journal.pending(lease: lease) == [first, command()])
}

@Test func journalAdapterPreservesKnownAcceptanceWhenDurableResolutionFails() async throws {
  let store = ControlledCommandStore()
  await store.fail(3)
  let transport = CommandTransport(store: store)
  let journal = PhoneCommandJournal(store: store)
  let adapter = JournaledGatewayCommands(journal: journal)
  let binding = try await adapter.bind(scope: scope(), connection: GatewayConnectionLease())
  do {
    _ = try await adapter.execute(command(), binding: binding, transport: transport)
    Issue.record("Resolution save should fail")
  } catch let failure as CommandDeliveryFailure {
    #expect(failure.command == command())
    #expect(failure.acknowledgment == .submitted("00000000-0000-4000-8000-0000000003e9"))
  }
  #expect(try await adapter.pending(binding) == [command()])
  #expect(await store.load(scope())?.commands == [command()])
  await store.fail(nil)
  await transport.offer(
    .init(
      found: true, requestId: command().requestID,
      stage: .settled, outcome: .dispatched))
  _ = try await adapter.check(command().requestID, binding: binding, transport: transport)
  #expect(try await adapter.pending(binding).isEmpty)
  #expect(await transport.dispatched == [command()])  // Check must not resend.
}

private func refusedCreation(_ number: Int = 1) -> PreparedConversationCommand {
  .create(
    .init(
      requestID: String(format: "00000000-0000-4000-8000-%012x", number),
      conversationID: String(format: "00000000-0000-4000-8000-%012x", number + 100),
      agent: "fixture", model: "missing"))
}

@Test func firstCreationRefusalReleasesReservationDurablyAndAllowsCorrectedIntent() async throws {
  let store = ControlledCommandStore()
  let transport = CommandTransport(store: store)
  let journal = PhoneCommandJournal(store: store)
  let adapter = JournaledGatewayCommands(journal: journal)
  let binding = try await adapter.bind(scope: scope(), connection: GatewayConnectionLease())
  await transport.refuse(.modelUnavailable)
  await #expect(throws: CommandDeliveryFailure.self) {
    try await adapter.execute(refusedCreation(), binding: binding, transport: transport)
  }
  #expect(try await adapter.pending(binding).isEmpty)
  let reopened = PhoneCommandJournal(store: store)
  let next = try await reopened.prepare(scope())
  #expect(try await reopened.pending(lease: next).isEmpty)
  await transport.refuse(nil)
  _ = try await adapter.execute(refusedCreation(2), binding: binding, transport: transport)
  #expect(await transport.dispatched == [refusedCreation(), refusedCreation(2)])
}

@Test func refusalAfterAnEarlierUncertainAttemptNeverDropsTheOriginalIdentity() async throws {
  let store = ControlledCommandStore()
  let transport = CommandTransport(store: store)
  let journal = PhoneCommandJournal(store: store)
  let adapter = JournaledGatewayCommands(journal: journal)
  let binding = try await adapter.bind(scope: scope(), connection: GatewayConnectionLease())
  await transport.dropACK(true)
  await #expect(throws: CommandDeliveryFailure.self) {
    try await adapter.execute(refusedCreation(), binding: binding, transport: transport)
  }
  let reopened = JournaledGatewayCommands(journal: PhoneCommandJournal(store: store))
  let next = try await reopened.bind(scope: scope(), connection: GatewayConnectionLease())
  await transport.dropACK(false)
  await transport.refuse(.modelUnavailable)
  await #expect(throws: CommandDeliveryFailure.self) {
    try await reopened.retry(refusedCreation().requestID, binding: next, transport: transport)
  }
  #expect(try await reopened.pending(next) == [refusedCreation()])
  #expect(await store.load(scope())?.attempts[refusedCreation().requestID] == 2)
}

@Test func failedAttemptOrRejectionPersistencePreservesIntentAndNeverClaimsRejection() async throws
{
  let store = ControlledCommandStore()
  let journal = PhoneCommandJournal(store: store)
  let transport = CommandTransport(store: store)
  let adapter = JournaledGatewayCommands(journal: journal)
  let binding = try await adapter.bind(scope: scope(), connection: GatewayConnectionLease())
  await store.fail(2)
  await #expect(throws: PhoneCommandStoreError.unavailable) {
    try await adapter.execute(refusedCreation(), binding: binding, transport: transport)
  }
  #expect(await transport.dispatched.isEmpty)
  #expect(await store.load(scope())?.attempts[refusedCreation().requestID] == 0)
  await store.fail(4)
  await transport.refuse(.modelUnavailable)
  do {
    _ = try await adapter.execute(refusedCreation(), binding: binding, transport: transport)
    Issue.record("Rejection persistence should fail")
  } catch let failure as CommandDeliveryFailure {
    #expect(failure.acknowledgment == nil)
    #expect(failure.underlying as? PhoneCommandStoreError == .unavailable)
  }
  #expect(try await adapter.pending(binding) == [refusedCreation()])
  #expect(await store.load(scope())?.attempts[refusedCreation().requestID] == 1)
}

@Test func concurrentAttemptAndHistoricalRecordsInvalidateSoleDispatchProof() async throws {
  let journal = PhoneCommandJournal(store: InMemoryCommandJournalStore())
  let lease = try await journal.prepare(scope())
  let intent = refusedCreation()
  try await journal.recordProductIntent(intent, lease: lease)
  #expect(try await journal.beginAttempt(intent, lease: lease))
  #expect(try await journal.beginAttempt(intent, lease: lease) == false)
  await #expect(throws: ConversationCommandError.conflict) {
    try await journal.reject(.init(command: intent, reason: .modelUnavailable), lease: lease)
  }
  #expect(try await journal.pending(lease: lease) == [intent])
  let encoded = try JSONEncoder().encode(PhoneCommands(commands: [intent]))
  var old = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
  old.removeValue(forKey: "attempts")
  let historical = try JSONDecoder().decode(
    PhoneCommands.self, from: JSONSerialization.data(withJSONObject: old))
  #expect(historical.attempts[intent.requestID] == 1)
  var invalid = historical
  invalid.attempts[intent.requestID] = -1
  #expect(throws: PhoneCommandStoreError.corrupt) { try invalid.validate() }
  invalid.attempts = [:]
  #expect(throws: PhoneCommandStoreError.corrupt) { try invalid.validate() }
}

@Test func cancellationDuringAttemptPersistenceNeverReachesTransport() async throws {
  let store = ControlledCommandStore()
  await store.block(2)
  let transport = CommandTransport(store: store)
  let adapter = JournaledGatewayCommands(journal: PhoneCommandJournal(store: store))
  let binding = try await adapter.bind(scope: scope(), connection: GatewayConnectionLease())
  let sending = Task {
    try await adapter.execute(refusedCreation(), binding: binding, transport: transport)
  }
  try await entered { await store.writes == 2 }
  sending.cancel()
  await store.release()
  await #expect(throws: CancellationError.self) { try await sending.value }
  #expect(await transport.dispatched.isEmpty)
  #expect(try await adapter.pending(binding) == [refusedCreation()])
  #expect(await store.load(scope())?.attempts[refusedCreation().requestID] == 1)
}

@Test func anotherJournalOwnerInvalidatesFirstAttemptRejectionViaCAS() async throws {
  let store = InMemoryCommandJournalStore()
  let first = PhoneCommandJournal(store: store)
  let lease = try await first.prepare(scope())
  try await first.recordProductIntent(refusedCreation(), lease: lease)
  #expect(try await first.beginAttempt(refusedCreation(), lease: lease))
  let second = PhoneCommandJournal(store: store)
  let next = try await second.prepare(scope())
  #expect(try await second.beginAttempt(refusedCreation(), lease: next) == false)
  await #expect(throws: PhoneCommandStoreError.changed) {
    try await first.reject(
      .init(command: refusedCreation(), reason: .modelUnavailable), lease: lease)
  }
  #expect(try await second.pending(lease: next) == [refusedCreation()])
  #expect(await store.load(scope())?.attempts[refusedCreation().requestID] == 2)
}

@Test func publicJournalExecutionCannotBypassProductAttemptAccounting() async throws {
  let store = ControlledCommandStore()
  let transport = CommandTransport(store: store)
  let journal = PhoneCommandJournal(store: store)
  let lease = try await journal.prepare(scope())
  try await journal.recordProductIntent(refusedCreation(), lease: lease)
  await transport.dropACK(true)
  await #expect(throws: NessaGatewayError.self) {
    try await journal.execute(
      refusedCreation(), lease: lease,
      connection: GatewayConnectionLease(), transport: transport)
  }
  #expect(await store.load(scope())?.attempts[refusedCreation().requestID] == 1)
  let adapter = JournaledGatewayCommands(journal: journal)
  let binding = try await adapter.bind(scope: scope(), connection: GatewayConnectionLease())
  await transport.dropACK(false)
  await transport.refuse(.modelUnavailable)
  await #expect(throws: CommandDeliveryFailure.self) {
    try await adapter.retry(refusedCreation().requestID, binding: binding, transport: transport)
  }
  #expect(try await adapter.pending(binding) == [refusedCreation()])
  #expect(await store.load(scope())?.attempts[refusedCreation().requestID] == 2)
}
@Test func scopeReplacementSettlesOldWriteAndFencesObsoleteCommands() async throws {
  let store = ControlledCommandStore()
  await store.block(1)
  let journal = PhoneCommandJournal(store: store)
  let lease = try await journal.prepare(scope())
  let old = Task { try await journal.record(command(), lease: lease) }
  try await entered { await store.writes == 1 }
  let replacement = Task { try await journal.prepare(scope("other")) }
  try await Task.sleep(for: .milliseconds(10))
  await store.release()
  await #expect(throws: ConversationCommandError.staleLease) { try await old.value }
  let next = try await replacement.value
  #expect(try await journal.pending(lease: next).isEmpty)
  await #expect(throws: ConversationCommandError.staleLease) {
    try await journal.record(command(2), lease: lease)
  }
  #expect(await store.load(scope())?.commands == [command()])
  let reopened = try await journal.prepare(scope())
  #expect(try await journal.pending(lease: reopened) == [command()])
}
@Test func journalQuotaNeverEvictsUncertainCommands() async throws {
  let store = ControlledCommandStore()
  let journal = PhoneCommandJournal(store: store)
  let lease = try await journal.prepare(scope())
  for index in 1...32 { try await journal.record(command(index), lease: lease) }
  await #expect(throws: PhoneCommandStoreError.quota) {
    try await journal.record(command(33), lease: lease)
  }
  #expect(try await journal.pending(lease: lease).count == 32)
  #expect(await store.load(scope())?.commands.count == 32)
}
@Test func journalFileRecreationIsPrivateAndCorruptionQuotaLinksAreRefused() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let store = PhoneCommandStore(root: root)
  try await store.save(PhoneCommands(commands: [command()]), scope: scope(), replacing: nil)
  let recreated = PhoneCommandStore(root: root)
  #expect(try await recreated.load(scope())?.commands == [command()])
  #expect(try await recreated.load(scope("other")) == nil)
  let file = root.appendingPathComponent(scope().key + ".json")
  let permissions =
    try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
  #expect(permissions?.intValue == 0o600)
  await #expect(throws: PhoneCommandStoreError.quota) {
    try await PhoneCommandStore(root: root, maximumBytes: 10).load(scope())
  }
  try Data("{bad".utf8).write(to: file)
  let journal = PhoneCommandJournal(store: recreated)
  await #expect(throws: PhoneCommandStoreError.corrupt) { try await journal.prepare(scope()) }
  #expect(try Data(contentsOf: file) == Data("{bad".utf8))
  try FileManager.default.removeItem(at: file)
  try FileManager.default.createSymbolicLink(
    at: file, withDestinationURL: root.appendingPathComponent("missing"))
  await #expect(throws: PhoneCommandStoreError.unavailable) { try await recreated.load(scope()) }
  await #expect(throws: PhoneCommandStoreError.unavailable) {
    try await recreated.save(PhoneCommands(commands: [command()]), scope: scope(), replacing: nil)
  }
}
@Test func receiptProgressIsKindSpecificAndAttachmentsAreFrozenInOrder() throws {
  let create = PreparedConversationCommand.create(
    .init(
      requestID: command().requestID,
      conversationID: command().conversationID, agent: "codex", model: "test-model"))
  #expect(
    try ConversationCommandReceipt(found: true, requestId: create.requestID, stage: .ready)
      .acknowledgment(for: create) == .created(create.conversationID))
  #expect(throws: ConversationCommandError.invalid) {
    try ConversationCommandReceipt(
      found: true, requestId: create.requestID, stage: .settled, outcome: .dispatched
    )
    .acknowledgment(for: create)
  }
  #expect(throws: ConversationCommandError.invalid) {
    try ConversationCommandReceipt(found: true, requestId: command().requestID, stage: .ready)
      .acknowledgment(for: command())
  }
  let images = ["a", "b"].map {
    NessaStoredAttachment(
      digest: "sha256:" + String(repeating: $0, count: 64), mimeType: "image/png", size: 8)
  }
  let photo = PreparedConversationCommand.submit(
    .init(
      requestID: command().requestID,
      conversationID: command().conversationID, executionID: "00000000-0000-4000-8000-0000000003e9",
      text: "", images: images))
  try photo.validate()
  #expect(
    try JSONDecoder().decode(PreparedConversationCommand.self, from: JSONEncoder().encode(photo))
      == photo)
}
@Test func separateStoresRefuseStaleInsertionAndResolutionWithoutLosingCommands() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let storeA = PhoneCommandStore(root: root)
  let storeB = PhoneCommandStore(root: root)
  let first = PhoneCommandJournal(store: storeA)
  let second = PhoneCommandJournal(store: storeB)
  let leaseA = try await first.prepare(scope())
  let leaseB = try await second.prepare(scope())
  try await first.record(command(1), lease: leaseA)
  await #expect(throws: PhoneCommandStoreError.changed) {
    try await second.record(command(2), lease: leaseB)
  }
  let refreshed = try await second.prepare(scope())
  try await second.record(command(2), lease: refreshed)
  await #expect(throws: PhoneCommandStoreError.changed) {
    try await first.resolve(
      command(1), acknowledgment: .submitted("00000000-0000-4000-8000-0000000003e9"), lease: leaseA)
  }
  #expect(try await storeA.load(scope())?.commands == [command(1), command(2)])
  let freshA = try await first.prepare(scope())
  try await first.resolve(
    command(1), acknowledgment: .submitted("00000000-0000-4000-8000-0000000003e9"), lease: freshA)
  #expect(try await storeB.load(scope())?.commands == [command(2)])
}
@Test func missingDocumentIsDifferentFromAnExistingEmptyJournal() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let first = PhoneCommandStore(root: root)
  let other = PhoneCommandStore(root: root)
  try await first.save(PhoneCommands(), scope: scope(), replacing: nil)
  await #expect(throws: PhoneCommandStoreError.changed) {
    try await other.save(PhoneCommands(commands: [command()]), scope: scope(), replacing: nil)
  }
  #expect(try await first.load(scope())?.commands.isEmpty == true)
}
@Test func commandLockIsStableAndContentionRefusesWithoutBlockingOrOverwriting() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let store = PhoneCommandStore(root: root)
  let original = PhoneCommands(commands: [command(1)])
  let updated = PhoneCommands(commands: [command(1), command(2)])
  try await store.save(original, scope: scope(), replacing: nil)
  let lock = root.appendingPathComponent(scope().key + ".lock")
  var before = stat()
  #expect(lstat(lock.path, &before) == 0)
  let descriptor = open(lock.path, O_RDWR | O_NOFOLLOW)
  #expect(descriptor >= 0)
  defer { close(descriptor) }
  #expect(flock(descriptor, LOCK_EX | LOCK_NB) == 0)
  let start = ContinuousClock.now
  await #expect(throws: PhoneCommandStoreError.unavailable) {
    try await store.save(updated, scope: scope(), replacing: original)
  }
  #expect(start.duration(to: .now) < .seconds(1))
  #expect(try await store.load(scope()) == original)
  #expect(flock(descriptor, LOCK_UN) == 0)
  try await store.save(updated, scope: scope(), replacing: original)
  var after = stat()
  #expect(lstat(lock.path, &after) == 0)
  #expect(before.st_ino == after.st_ino)
  #expect(after.st_mode & 0o777 == 0o600)
}

@Test func uploadedFilenameBytesAreFrozenAcrossCanonicalUnicodeForms() async throws {
  let store = ControlledCommandStore()
  let journal = PhoneCommandJournal(store: store)
  let lease = try await journal.prepare(scope())
  let make: (String) -> PreparedConversationCommand = { name in
    .submit(
      .init(
        requestID: "00000000-0000-4000-8000-000000000001",
        conversationID: "00000000-0000-4000-8000-100000000001",
        executionID: "00000000-0000-4000-8000-000000001001", text: "",
        uploads: [
          .init(
            digest: "sha256:" + String(repeating: "a", count: 64), mimeType: "text/plain", size: 1,
            name: name)
        ]))
  }
  let original = make("é.txt")
  let changed = make("e\u{301}.txt")
  #expect(original != changed)
  try await journal.recordProductIntent(original, lease: lease)
  await #expect(throws: ConversationCommandError.conflict) {
    try await journal.recordProductIntent(changed, lease: lease)
  }
}
