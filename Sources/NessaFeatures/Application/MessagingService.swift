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
  public func list() async throws -> NessaConversationList { try await repository.list() }
  public func read(_ id: String) async throws -> NessaConversationView {
    try await repository.read(id)
  }
  public func create(agent: String?) async throws -> String {
    try await repository.create(agent: agent)
  }
  public func send(_ text: String, attachments: [DraftAttachment] = [], conversationID: String)
    async throws
  {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
    else { throw NessaGatewayError.rejected("Write a message first.") }
    guard text.utf8.count <= 8192 else {
      throw NessaGatewayError.rejected("Messages must be at most 8,192 UTF-8 bytes.")
    }
    try repository.attachmentPolicy.validate(attachments)
    try await repository.send(text, attachments: attachments, conversationID: conversationID)
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
