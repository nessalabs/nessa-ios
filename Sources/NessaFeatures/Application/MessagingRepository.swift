import Foundation

/// Application port implemented by the product WebSocket adapter.
public protocol MessagingRepository: Sendable {
  var attachmentPolicy: AttachmentPolicy { get }
  func connect(address: String, credential: String, instance: String) async throws
  func list() async throws -> NessaConversationList
  func read(_ id: String) async throws -> NessaConversationView
  func create(agent: String?, model: String?) async throws -> String
  @discardableResult
  func send(_ text: String, attachments: [DraftAttachment], conversationID: String) async throws
    -> String
  func answer(_ permission: NessaPermission, option: NessaPermission.Option, conversationID: String)
    async throws
  func delete(_ conversationID: String) async throws
  func imageData(for attachment: NessaImageAttachment) async throws -> Data?
  func disconnect() async
}

public protocol NessaCredentialStoring: Sendable {
  func load() -> String?
  func save(_ credential: String) throws
}

extension MessagingRepository {
  public var attachmentPolicy: AttachmentPolicy { .development }
  public func imageData(for attachment: NessaImageAttachment) async throws -> Data? { nil }
  @discardableResult
  public func send(_ text: String, conversationID: String) async throws -> String {
    try await send(text, attachments: [], conversationID: conversationID)
  }
}
