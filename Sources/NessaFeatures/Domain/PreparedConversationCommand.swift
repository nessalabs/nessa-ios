import Foundation

/// A user intent frozen before submission. Retrying changes no field or identity.
public enum PreparedConversationCommand: Codable, Sendable, Equatable {
  public struct Creation: Codable, Sendable, Equatable {
    public let requestID: String
    public let conversationID: String
    public let agent: String?
    public let model: String?
    public init(requestID: String, conversationID: String, agent: String?, model: String?) {
      self.requestID = requestID
      self.conversationID = conversationID
      self.agent = agent
      self.model = model
    }
  }
  public struct Submission: Codable, Sendable, Equatable {
    public let requestID: String
    public let conversationID: String
    public let executionID: String
    public let text: String
    public let images: [NessaImageAttachment]
    public init(
      requestID: String, conversationID: String, executionID: String, text: String,
      images: [NessaImageAttachment] = []
    ) {
      self.requestID = requestID
      self.conversationID = conversationID
      self.executionID = executionID
      self.text = text
      self.images = images
    }
  }
  case create(Creation)
  case submit(Submission)
  public var requestID: String {
    switch self {
    case .create(let value): value.requestID
    case .submit(let value): value.requestID
    }
  }
  public var conversationID: String {
    switch self {
    case .create(let value): value.conversationID
    case .submit(let value): value.conversationID
    }
  }
  public func validate() throws {
    func uuid(_ value: String) -> Bool {
      UUID(uuidString: value)?.uuidString.lowercased() == value
    }
    guard uuid(requestID), uuid(conversationID) else { throw ConversationCommandError.invalid }
    switch self {
    case .create(let value):
      guard
        [value.agent, value.model].allSatisfy({ hint in
          guard let hint else { return true }
          return !hint.isEmpty && hint.utf8.count <= 256
        })
      else { throw ConversationCommandError.invalid }
    case .submit(let value):
      guard uuid(value.executionID), value.text.utf8.count <= 8192,
        !value.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          || !value.images.isEmpty,
        value.images.count <= 8,
        value.images.allSatisfy({ image in
          image.size > 0 && image.size <= 5 * 1024 * 1024
            && ["image/png", "image/jpeg", "image/gif", "image/webp"].contains(image.mimeType)
            && image.digest.hasPrefix("sha256:") && image.digest.count == 71
            && image.digest.dropFirst(7).utf8.allSatisfy({
              (48...57).contains($0) || (97...102).contains($0)
            })
        }), value.images.reduce(0, { $0 + $1.size }) <= 10 * 1024 * 1024
      else { throw ConversationCommandError.invalid }
    }
  }
}
public enum ConversationCommandError: Error, Sendable, Equatable {
  case invalid, conflict, staleLease, unresolved
}
public enum ConversationCommandAcknowledgment: Sendable, Equatable {
  case created(String)
  case submitted(String)
  public func validates(_ command: PreparedConversationCommand) -> Bool {
    switch (self, command) {
    case (.created(let id), .create(let value)): id == value.conversationID
    case (.submitted(let id), .submit(let value)): id == value.executionID
    default: false
    }
  }
}
public struct ConversationCommandReceipt: Codable, Sendable, Equatable {
  public enum Stage: String, Codable, Sendable { case accepted, attempted, ready, settled }
  public enum Outcome: String, Codable, Sendable {
    case dispatched, withdrawn, cancelled
    case alreadyFinal = "already_final"
  }
  public let found: Bool
  public let requestId: String
  public let stage: Stage?
  public let outcome: Outcome?
  public init(found: Bool, requestId: String, stage: Stage? = nil, outcome: Outcome? = nil) {
    self.found = found
    self.requestId = requestId
    self.stage = stage
    self.outcome = outcome
  }
  /// Absence and in-progress receipts do not prove that a command was never admitted.
  public func acknowledgment(for command: PreparedConversationCommand) throws
    -> ConversationCommandAcknowledgment?
  {
    guard requestId == command.requestID else { throw ConversationCommandError.invalid }
    if !found {
      guard stage == nil, outcome == nil else { throw ConversationCommandError.invalid }
      return nil
    }
    guard let stage else { throw ConversationCommandError.invalid }
    switch command {
    case .create(let value):
      guard stage != .settled, outcome == nil else { throw ConversationCommandError.invalid }
      return stage == .ready ? .created(value.conversationID) : nil
    case .submit(let value):
      if stage == .settled {
        guard outcome == .dispatched else { throw ConversationCommandError.invalid }
        return .submitted(value.executionID)
      }
      guard stage != .ready, outcome == nil else { throw ConversationCommandError.invalid }
      return nil
    }
  }
}
