import Foundation

/// Application use cases. Repository selection is supplied by the composition root.
public struct MessagingService: Sendable {
  private let repository: any MessagingRepository
  private let directory: (any AgentDirectory)?
  public init(repository: any MessagingRepository, directory: (any AgentDirectory)? = nil) {
    self.repository = repository
    self.directory = directory
  }
  public func imageData(for attachment: NessaImageAttachment) async throws -> Data? {
    try await repository.imageData(for: attachment)
  }
  public var attachmentPolicy: AttachmentPolicy { repository.attachmentPolicy }
  public func agents() async throws -> [AgentProfile] { try await directory?.agents() ?? [] }
  public func connect(address: String, credential: String, instance: String) async throws {
    try await repository.connect(address: address, credential: credential, instance: instance)
  }
  public func follow(_ id: String?, after: ConversationCursor? = nil) async throws
    -> AsyncThrowingStream<ConversationUpdate, Error>?
  {
    guard let source = repository as? any ConversationFollowing else { return nil }
    return try await source.follow(id, after: after)
  }
  /// Follow live replacements; only lag/source closure are retryable on this connection.
  public func watch(
    _ id: String?, after: ConversationCursor? = nil,
    apply: @Sendable (ConversationUpdate) async throws -> Void
  ) async throws {
    var cursor = after
    while !Task.isCancelled {
      do {
        guard let stream = try await follow(id, after: cursor) else {
          // Custom repositories without a feed can still provide bounded snapshots.
          if let id {
            let view = try await read(id)
            try await apply(
              .view(try ConversationCursor(incarnation: "snapshot", position: "0"), view))
          } else {
            try await apply(.list(try await list()))
          }
          try await Task.sleep(for: .seconds(2))
          continue
        }
        for try await update in stream {
          try Task.checkCancellation()
          switch update {
          case .list:
            guard id == nil else { throw NessaGatewayError.invalidFrame }
          case .view(let next, let view):
            guard view.conversationId == id else { throw NessaGatewayError.invalidFrame }
            if let old = cursor, old.incarnation == next.incarnation, next.offset < old.offset {
              continue
            }
            cursor = next
          }
          try await apply(update)
        }
        return
      } catch let ended as ConversationFeedEnded
        where ended.reason == .lagging || ended.reason == .sourceClosed
      {
        try await Task.sleep(for: .milliseconds(200))
      }
    }
  }
  public func list() async throws -> NessaConversationList { try await repository.list() }
  public func read(_ id: String) async throws -> NessaConversationView {
    try await repository.read(id)
  }
  public func create(agent: String?, model: String? = nil) async throws -> String {
    try await repository.create(agent: agent, model: model)
  }
  @discardableResult
  public func send(
    _ text: String, attachments: [DraftAttachment] = [], reply: MessageReply? = nil,
    conversationID: String
  ) async throws -> String {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
    else { throw NessaGatewayError.rejected("Write a message first.") }
    let contextualText = reply?.contextualizing(text) ?? text
    guard contextualText.utf8.count <= 8192 else {
      throw NessaGatewayError.rejected("Messages must be at most 8,192 UTF-8 bytes.")
    }
    try repository.attachmentPolicy.validate(attachments)
    return try await repository.send(
      contextualText, attachments: attachments, conversationID: conversationID)
  }
  public func delete(_ id: String) async throws { try await repository.delete(id) }
  public func answer(
    _ permission: NessaPermission, option: NessaPermission.Option, conversationID: String
  ) async throws {
    guard permission.options.contains(where: { $0.id == option.id }) else {
      throw NessaGatewayError.rejected("Choose one of the offered permission options.")
    }
    try await repository.answer(permission, option: option, conversationID: conversationID)
  }
  public func disconnect() async { await repository.disconnect() }
}
