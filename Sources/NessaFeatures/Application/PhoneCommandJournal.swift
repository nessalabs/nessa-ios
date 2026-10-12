import Foundation

public struct PhoneCommands: Codable, Sendable, Equatable {
  public var schema = 1
  public var commands: [PreparedConversationCommand]
  /// 0: no dispatch; 1: one dispatch; 2: multiple or conservatively unknown.
  public var attempts: [String: Int]
  public init(commands: [PreparedConversationCommand] = [], attempts: [String: Int]? = nil) {
    self.commands = commands
    self.attempts =
      attempts
      ?? Dictionary(commands.map { ($0.requestID, 1) }, uniquingKeysWith: { first, _ in first })
  }
  private enum CodingKeys: String, CodingKey { case schema, commands, attempts }
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    schema = try container.decode(Int.self, forKey: .schema)
    commands = try container.decode([PreparedConversationCommand].self, forKey: .commands)
    // Historical records may already have reached the gateway.
    attempts =
      try container.decodeIfPresent([String: Int].self, forKey: .attempts)
      ?? Dictionary(commands.map { ($0.requestID, 1) }, uniquingKeysWith: { first, _ in first })
  }
  public func validate() throws {
    guard schema == 1, commands.count <= 32,
      Set(commands.map(\.requestID)).count == commands.count,
      Set(attempts.keys) == Set(commands.map(\.requestID)),
      attempts.values.allSatisfy({ (0...2).contains($0) })
    else { throw PhoneCommandStoreError.corrupt }
    do { for command in commands { try command.validate() } } catch {
      throw PhoneCommandStoreError.corrupt
    }
  }
}
public enum PhoneCommandStoreError: Error, Sendable, Equatable {
  case corrupt, quota, unavailable, changed
}
public protocol CommandJournalStoring: Sendable {
  func load(_ scope: PhoneCacheScope) async throws -> PhoneCommands?
  func save(_ commands: PhoneCommands, scope: PhoneCacheScope, replacing expected: PhoneCommands?)
    async throws
}
public protocol PreparedCommandTransport: Sendable {
  func dispatch(
    _ command: PreparedConversationCommand, connection: GatewayConnectionLease,
    scope: PhoneCacheScope
  )
    async throws -> ConversationCommandAcknowledgment
  func receipt(
    _ command: PreparedConversationCommand, connection: GatewayConnectionLease,
    scope: PhoneCacheScope
  )
    async throws -> ConversationCommandReceipt
}

/// Uncertain intents are never evicted or replayed by a reconnect loop.
public actor PhoneCommandJournal {
  public struct Lease: Sendable, Equatable {
    fileprivate let id = UUID()
    fileprivate let scope: PhoneCacheScope
  }
  private struct Write {
    let id: UUID
    let task: Task<Void, Error>
  }
  private let store: any CommandJournalStoring
  private var lease: Lease?
  private var values = PhoneCommands()
  private var durable: PhoneCommands?
  private var writer: Write?
  private var loaded = false
  public init(store: any CommandJournalStoring) { self.store = store }
  public func prepare(_ scope: PhoneCacheScope) async throws -> Lease {
    let next = Lease(scope: scope)
    lease = next
    loaded = false
    await settle()
    try check(next)
    let saved = try await store.load(scope)
    try check(next)
    try saved?.validate()
    values = saved ?? PhoneCommands()
    durable = saved
    loaded = true
    return next
  }
  public func pending(lease expected: Lease) async throws -> [PreparedConversationCommand] {
    await settle()
    try requireLoaded(expected)
    return values.commands
  }
  public func record(_ command: PreparedConversationCommand, lease expected: Lease) async throws {
    try await record(command, lease: expected, productIntent: false)
  }
  /// Admission and reservation share the same serialized journal transaction.
  public func recordProductIntent(_ command: PreparedConversationCommand, lease expected: Lease)
    async throws
  {
    try await record(command, lease: expected, productIntent: true)
  }
  private func record(
    _ command: PreparedConversationCommand, lease expected: Lease,
    productIntent: Bool
  ) async throws {
    await settle()
    try requireLoaded(expected)
    try Task.checkCancellation()
    try command.validate()
    if let existing = values.commands.first(where: { $0.requestID == command.requestID }) {
      guard existing == command else { throw ConversationCommandError.conflict }
      return
    }
    if productIntent,
      let existing = values.commands.first(where: { pending in
        switch (command, pending) {
        case (.create, .create): true
        case (.submit, .submit): command.conversationID == pending.conversationID
        default: false
        }
      })
    {
      throw CommandAdmissionBlocked(requestID: existing.requestID)
    }
    guard values.commands.count < 32 else { throw PhoneCommandStoreError.quota }
    var next = values
    next.commands.append(command)
    next.attempts[command.requestID] = productIntent ? 0 : 1
    try await commit(next, lease: expected)
  }
  /// A crash after this save is uncertain, even if the process never reached dispatch.
  public func beginAttempt(_ command: PreparedConversationCommand, lease expected: Lease)
    async throws -> Bool
  {
    await settle()
    try requireLoaded(expected)
    try Task.checkCancellation()
    guard values.commands.contains(command), let count = values.attempts[command.requestID] else {
      throw ConversationCommandError.conflict
    }
    var next = values
    next.attempts[command.requestID] = min(2, count + 1)
    try await commit(next, lease: expected)
    try Task.checkCancellation()
    return count == 0
  }
  /// A refusal of a later attempt says nothing about an earlier uncertain dispatch.
  public func reject(_ refusal: ConversationCommandRefusal, lease expected: Lease) async throws {
    await settle()
    try requireLoaded(expected)
    try Task.checkCancellation()
    guard refusal.valid, values.commands.contains(refusal.command),
      values.attempts[refusal.command.requestID] == 1
    else { throw ConversationCommandError.conflict }
    var next = values
    next.commands.removeAll { $0.requestID == refusal.command.requestID }
    next.attempts.removeValue(forKey: refusal.command.requestID)
    try await commit(next, lease: expected)
  }
  public func resolve(
    _ command: PreparedConversationCommand,
    acknowledgment: ConversationCommandAcknowledgment, lease expected: Lease
  ) async throws {
    await settle()
    try requireLoaded(expected)
    try Task.checkCancellation()
    guard acknowledgment.validates(command),
      values.commands.first(where: { $0.requestID == command.requestID }) == command
    else { throw ConversationCommandError.conflict }
    var next = values
    next.commands.removeAll { $0.requestID == command.requestID }
    next.attempts.removeValue(forKey: command.requestID)
    try await commit(next, lease: expected)
  }
  /// Callers explicitly retry this exact command. Persistence precedes every dispatch.
  public func execute(
    _ command: PreparedConversationCommand, lease expected: Lease,
    connection: GatewayConnectionLease, transport: any PreparedCommandTransport
  ) async throws
    -> ConversationCommandAcknowledgment
  {
    try await record(command, lease: expected)
    _ = try await beginAttempt(command, lease: expected)
    try requireLoaded(expected)
    try Task.checkCancellation()
    let acknowledgment = try await transport.dispatch(
      command, connection: connection, scope: expected.scope)
    try await resolve(command, acknowledgment: acknowledgment, lease: expected)
    return acknowledgment
  }
  /// Lookup alone is read-only. The caller must observe and explicitly resolve a confirmation.
  public func lookup(
    _ command: PreparedConversationCommand, lease expected: Lease,
    connection: GatewayConnectionLease, transport: any PreparedCommandTransport
  ) async throws
    -> ConversationCommandAcknowledgment?
  {
    await settle()
    try requireLoaded(expected)
    guard values.commands.contains(command) else { throw ConversationCommandError.conflict }
    try Task.checkCancellation()
    let receipt = try await transport.receipt(
      command, connection: connection, scope: expected.scope)
    try requireLoaded(expected)
    return try receipt.acknowledgment(for: command)
  }
  private func check(_ expected: Lease) throws {
    guard lease == expected else { throw ConversationCommandError.staleLease }
  }
  private func requireLoaded(_ expected: Lease) throws {
    try check(expected)
    guard loaded else { throw PhoneCommandStoreError.unavailable }
  }
  private func settle() async {
    while let writing = writer {
      _ = try? await writing.task.value
      if writer?.id == writing.id { writer = nil }
    }
  }
  private func commit(_ next: PhoneCommands, lease expected: Lease) async throws {
    let id = UUID()
    let store = store
    let previous = durable
    let task = Task {
      try await store.save(next, scope: expected.scope, replacing: previous)
      try requireLoaded(expected)
      values = next
      durable = next
    }
    writer = Write(id: id, task: task)
    defer { if writer?.id == id { writer = nil } }
    try await task.value
    try requireLoaded(expected)
  }
}
