import Foundation

/// Adapts the application journal to a particular authenticated socket binding.
struct JournaledGatewayCommands: Sendable {
  struct Binding: Sendable {
    let journal: PhoneCommandJournal.Lease
    let connection: GatewayConnectionLease
    let scope: PhoneCacheScope
  }
  let journal: PhoneCommandJournal
  func bind(scope: PhoneCacheScope, connection: GatewayConnectionLease) async throws -> Binding {
    Binding(journal: try await journal.prepare(scope), connection: connection, scope: scope)
  }
  func pending(_ binding: Binding) async throws -> [PreparedConversationCommand] {
    try await journal.pending(lease: binding.journal)
  }
  func execute(
    _ command: PreparedConversationCommand, binding: Binding,
    transport: any PreparedCommandTransport
  ) async throws -> ResolvedConversationCommand {
    try await journal.recordProductIntent(command, lease: binding.journal)
    let firstAttempt = try await journal.beginAttempt(command, lease: binding.journal)
    var acknowledged: ConversationCommandAcknowledgment?
    do {
      try Task.checkCancellation()
      let result = try await transport.dispatch(
        command, connection: binding.connection, scope: binding.scope)
      acknowledged = result
      try await journal.resolve(command, acknowledgment: result, lease: binding.journal)
      return ResolvedConversationCommand(command: command, acknowledgment: result)
    } catch {
      if firstAttempt, acknowledged == nil, let refusal = error as? ConversationCommandRefusal,
        refusal.command == command
      {
        do { try await journal.reject(refusal, lease: binding.journal) } catch {
          throw CommandDeliveryFailure(command: command, underlying: error)
        }
      }
      throw CommandDeliveryFailure(
        command: command, acknowledgment: acknowledged, underlying: error)
    }
  }
  func check(_ requestID: String, binding: Binding, transport: any PreparedCommandTransport)
    async throws -> ResolvedConversationCommand?
  {
    let command = try await find(requestID, binding: binding)
    guard
      let confirmation = try await journal.lookup(
        command, lease: binding.journal,
        connection: binding.connection, transport: transport)
    else { return nil }
    return try await resolve(command, confirmation: confirmation, binding: binding)
  }
  func retry(_ requestID: String, binding: Binding, transport: any PreparedCommandTransport)
    async throws -> ResolvedConversationCommand
  {
    let command = try await find(requestID, binding: binding)
    if let confirmation = try await journal.lookup(
      command, lease: binding.journal,
      connection: binding.connection, transport: transport)
    {
      return try await resolve(command, confirmation: confirmation, binding: binding)
    }
    return try await execute(command, binding: binding, transport: transport)
  }
  private func find(_ requestID: String, binding: Binding) async throws
    -> PreparedConversationCommand
  {
    guard let command = try await pending(binding).first(where: { $0.requestID == requestID })
    else {
      throw ConversationCommandError.conflict
    }
    return command
  }
  private func resolve(
    _ command: PreparedConversationCommand,
    confirmation: ConversationCommandAcknowledgment, binding: Binding
  ) async throws
    -> ResolvedConversationCommand
  {
    do {
      try await journal.resolve(command, acknowledgment: confirmation, lease: binding.journal)
      return ResolvedConversationCommand(command: command, acknowledgment: confirmation)
    } catch {
      throw CommandDeliveryFailure(
        command: command, acknowledgment: confirmation, underlying: error)
    }
  }
}
