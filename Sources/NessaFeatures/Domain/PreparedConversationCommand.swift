import Foundation

/// A user intent frozen before submission. Retrying changes no field or identity.
public enum PreparedConversationCommand: Codable, Sendable, Equatable {
  public struct Creation: Codable, Sendable, Equatable {
    public let requestID: String
    public let conversationID: String
    public let agent: String?
    public let model: String?
    /// The channel the chat starts in; nil is the default channel.
    public let channelID: String?
    public init(
      requestID: String, conversationID: String, agent: String?, model: String?,
      channelID: String? = nil
    ) {
      self.requestID = requestID
      self.conversationID = conversationID
      self.agent = agent
      self.model = model
      self.channelID = channelID
    }
  }
  public struct Submission: Codable, Sendable, Equatable {
    public let requestID: String
    public let conversationID: String
    public let executionID: String
    public let text: String
    public let images: [NessaStoredAttachment]
    public let uploads: [NessaUploadedFile]
    public let replyTo: String?
    public init(
      requestID: String, conversationID: String, executionID: String, text: String,
      images: [NessaStoredAttachment] = [], uploads: [NessaUploadedFile] = [],
      replyTo: String? = nil
    ) {
      self.requestID = requestID
      self.conversationID = conversationID
      self.executionID = executionID
      self.text = text
      self.images = images
      self.uploads = uploads
      self.replyTo = replyTo
    }
    private enum CodingKeys: String, CodingKey {
      case requestID, conversationID, executionID, text, images, uploads, replyTo
    }
    public init(from decoder: Decoder) throws {
      let values = try decoder.container(keyedBy: CodingKeys.self)
      self.init(
        requestID: try values.decode(String.self, forKey: .requestID),
        conversationID: try values.decode(String.self, forKey: .conversationID),
        executionID: try values.decode(String.self, forKey: .executionID),
        text: try values.decode(String.self, forKey: .text),
        images: try values.decode([NessaStoredAttachment].self, forKey: .images),
        uploads: try values.decodeIfPresent([NessaUploadedFile].self, forKey: .uploads) ?? [],
        replyTo: try values.decodeIfPresent(String.self, forKey: .replyTo))
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
        value.replyTo == nil
          || (value.replyTo?.isEmpty == false && (value.replyTo?.utf8.count ?? 0) <= 1024),
        !value.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          || !value.images.isEmpty || !value.uploads.isEmpty,
        AttachmentReferences.valid(images: value.images, uploads: value.uploads)
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
