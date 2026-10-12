import Foundation

public struct ResolvedConversationCommand: Sendable {
  public let command: PreparedConversationCommand
  public let acknowledgment: ConversationCommandAcknowledgment
  public init(
    command: PreparedConversationCommand, acknowledgment: ConversationCommandAcknowledgment
  ) {
    self.command = command
    self.acknowledgment = acknowledgment
  }
}
public protocol CommandRecoveryProviding: Sendable {
  func create(_ intent: PreparedConversationCommand.Creation) async throws -> String
  func send(
    _ text: String, attachments: [DraftAttachment], conversationID: String,
    identity: MessageCommandIdentity, replyTo: String?
  ) async throws -> String
  func pendingCommands() async throws -> [PreparedConversationCommand]
  func checkCommand(_ requestID: String) async throws -> ResolvedConversationCommand?
  func retryCommand(_ requestID: String) async throws -> ResolvedConversationCommand
}
public struct CommandAdmissionBlocked: LocalizedError, Sendable {
  public let requestID: String
  public init(requestID: String) { self.requestID = requestID }
  public var errorDescription: String? { "Check or retry the pending delivery first." }
}
/// Acceptance can be known while local durable resolution remains unfinished.
public struct CommandDeliveryFailure: LocalizedError, Sendable {
  public let command: PreparedConversationCommand
  public let acknowledgment: ConversationCommandAcknowledgment?
  public let underlying: any Error
  public init(
    command: PreparedConversationCommand, acknowledgment: ConversationCommandAcknowledgment? = nil,
    underlying: any Error
  ) {
    self.command = command
    self.acknowledgment = acknowledgment
    self.underlying = underlying
  }
  public var errorDescription: String? { underlying.localizedDescription }
}
