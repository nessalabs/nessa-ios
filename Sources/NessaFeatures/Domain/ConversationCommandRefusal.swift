import Foundation

/// Only audited, operation-specific refusals can prove a sole dispatch had no effect.
public struct ConversationCommandRefusal: LocalizedError, Sendable, Equatable {
  public enum Reason: String, Sendable {
    case modelUnavailable, agentNotConfigured, imagesUnsupported
  }
  public let command: PreparedConversationCommand
  public let reason: Reason
  public init(command: PreparedConversationCommand, reason: Reason) {
    self.command = command
    self.reason = reason
  }
  public var valid: Bool {
    switch (command, reason) {
    case (.create, .modelUnavailable), (.create, .agentNotConfigured),
      (.submit, .imagesUnsupported):
      true
    default: false
    }
  }
  public var errorDescription: String? {
    switch reason {
    case .modelUnavailable: "This model is no longer available. Choose another model."
    case .agentNotConfigured: "This agent is no longer available on the gateway."
    case .imagesUnsupported: "This chat’s model cannot receive photos. Start an image-capable chat."
    }
  }
}
