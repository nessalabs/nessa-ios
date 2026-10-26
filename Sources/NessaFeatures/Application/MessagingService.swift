import Foundation

/// Application use cases. Repository selection is supplied by the composition root.
public struct MessagingService: Sendable, GatewayConversationSharingProviding,
  GatewayConversationDeleting
{
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
  public func authenticatedSession(for lease: GatewayConnectionLease) async throws
    -> AuthenticatedGatewaySession
  {
    guard let source = repository as? any AuthenticatedGatewaySessionProviding else {
      throw NessaGatewayError.incompatibleProtocol
    }
    return try await source.authenticatedSession(for: lease)
  }
  public func pendingPairings(on lease: GatewayConnectionLease) async throws
    -> GatewayPairingReceipt<[GatewayPairingStatus]>
  {
    guard let pairing = repository as? any GatewayPairingManaging else {
      throw NessaGatewayError.incompatibleProtocol
    }
    return try await pairing.pendingPairings(on: lease)
  }
  private func sharingPort() throws -> any GatewayConversationSharingProviding {
    guard let port = repository as? any GatewayConversationSharingProviding else {
      throw NessaGatewayError.incompatibleProtocol
    }
    return port
  }
  public func ownerConversationChoices(on lease: GatewayConnectionLease) async throws
    -> PhoneConversationShareReceipt<NessaConversationList>
  {
    try await sharingPort().ownerConversationChoices(on: lease)
  }
  public func conversationShares(_ id: String, on lease: GatewayConnectionLease) async throws
    -> PhoneConversationShareReceipt<[PhoneConversationShare]>
  {
    try await sharingPort().conversationShares(id, on: lease)
  }
  public func setConversationRead(
    _ intent: PhoneConversationShareIntent, on lease: GatewayConnectionLease
  )
    async throws -> PhoneConversationShareReceipt<PhoneConversationShareAcknowledgment>
  {
    try await sharingPort().setConversationRead(intent, on: lease)
  }
  private func deletionPort() throws -> any GatewayConversationDeleting {
    guard let port = repository as? any GatewayConversationDeleting else {
      throw NessaGatewayError.incompatibleProtocol
    }
    return port
  }
  public func deleteConversation(_ intent: PhoneDeletionIntent, on lease: GatewayConnectionLease)
    async throws -> PhoneDeletionReceipt<PhoneDeletionAcknowledgment>
  {
    try await deletionPort().deleteConversation(intent, on: lease)
  }
  public func observeDeletion(_ id: String, on lease: GatewayConnectionLease) async throws
    -> PhoneDeletionReceipt<PhoneDeletionObservation>
  {
    try await deletionPort().observeDeletion(id, on: lease)
  }
  @discardableResult
  public func connect(address: String, credential: String, instance: String) async throws
    -> GatewayConnectionLease?
  {
    if let owner = repository as? any ConnectionLeasing {
      return try await owner.connectWithLease(
        address: address, credential: credential, instance: instance)
    }
    try await repository.connect(address: address, credential: credential, instance: instance)
    return nil
  }
  /// The product session over the paired Mac's native link.
  func connectLinked(_ exchange: any GatewayProductExchange, scope: PhoneCacheScope)
    async throws -> GatewayConnectionLease
  {
    guard let linked = repository as? any LinkedProductConnecting else {
      _ = await exchange.close()
      throw NessaGatewayError.incompatibleProtocol
    }
    return try await linked.connectLinked(exchange, scope: scope)
  }
  /// Waits until the closed linked connections released their native session.
  func drainLinked() async throws {
    try await (repository as? any LinkedProductConnecting)?.drainLinked()
  }
  public func retire(_ lease: GatewayConnectionLease?) async {
    guard let lease, let owner = repository as? any ConnectionLeasing else { return }
    await owner.retire(lease)
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
  public func listArchived() async throws -> NessaConversationList {
    try await repository.listArchived()
  }
  public func setArchived(_ archived: Bool, conversationID: String) async throws {
    try await repository.setArchived(archived, conversationID: conversationID)
  }
  public func read(_ id: String) async throws -> NessaConversationView {
    try await repository.read(id)
  }
  public func create(agent: String?, model: String? = nil) async throws -> String {
    try await create(
      .init(
        requestID: UUID().uuidString.lowercased(),
        conversationID: UUID().uuidString.lowercased(), agent: agent, model: model))
  }
  public func create(_ intent: PreparedConversationCommand.Creation) async throws -> String {
    if let commands = repository as? any CommandRecoveryProviding {
      return try await commands.create(intent)
    }
    return try await repository.create(agent: intent.agent, model: intent.model)
  }
  public func pendingCommands() async throws -> [PreparedConversationCommand] {
    try await (repository as? any CommandRecoveryProviding)?.pendingCommands() ?? []
  }
  public func checkCommand(_ requestID: String) async throws -> ResolvedConversationCommand? {
    try await (repository as? any CommandRecoveryProviding)?.checkCommand(requestID)
  }
  public func retryCommand(_ requestID: String) async throws -> ResolvedConversationCommand {
    guard let commands = repository as? any CommandRecoveryProviding else {
      throw NessaGatewayError.incompatibleProtocol
    }
    return try await commands.retryCommand(requestID)
  }
  @discardableResult
  public func send(
    _ text: String, attachments: [DraftAttachment] = [], reply: MessageReply? = nil,
    conversationID: String, identity: MessageCommandIdentity = MessageCommandIdentity()
  ) async throws -> String {
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
    else { throw NessaGatewayError.rejected("Write a message first.") }
    let contextualText = reply?.contextualizing(text) ?? text
    guard contextualText.utf8.count <= 8192 else {
      throw NessaGatewayError.rejected("Messages must be at most 8,192 UTF-8 bytes.")
    }
    try repository.attachmentPolicy.validate(attachments)
    if let commands = repository as? any CommandRecoveryProviding {
      return try await commands.send(
        contextualText, attachments: attachments,
        conversationID: conversationID, identity: identity, replyTo: reply?.id)
    }
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
