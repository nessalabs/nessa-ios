import CryptoKit
import Foundation

/// Native implementation of Nessa's product v1 req/res protocol. Commands are never replayed.
public actor NessaGatewayClient: MessagingRepository, AgentDirectory, ChannelDirectory,
  ReviewNoticeSource, ConversationFollowing,
  ConnectionLeasing, PreparedCommandTransport, CommandRecoveryProviding,
  AuthenticatedGatewaySessionProviding, GatewayPairingManaging
{
  public nonisolated var attachmentPolicy: AttachmentPolicy { .nessa }
  private var imageCache: AttachmentImageCache?
  public func imageData(for attachment: NessaImageAttachment) async throws -> Data? {
    return await imageCache?.read(attachment.digest)
  }
  private var uploadURL: URL?
  private var socket: URLSessionWebSocketTask?
  private var product: (any GatewayProductExchange)?
  private struct ProductDrain {
    let exchange: any GatewayProductExchange
    let task: Task<GatewayProductCloseObservation, Never>
  }
  // Actual child identity, never a native wire request ID or correlation map.
  private var productDrains: [ObjectIdentifier: ProductDrain] = [:]
  private var reader: Task<Void, Never>?
  private struct PendingRequest {
    let continuation: CheckedContinuation<Data, Error>
    let strictEnvelope: Bool
    let failure: @Sendable (String?, String?, Data?) -> any Error
  }
  private var pending: [String: PendingRequest] = [:]
  private var timeouts: [String: Task<Void, Never>] = [:]
  /// The last waiting-reviews announcement on this connection, and who is listening for the
  /// next. Both end with the connection.
  private var latestReviews: WaitingReviews?
  private var reviewListeners: [UUID: AsyncStream<WaitingReviews>.Continuation] = [:]
  private var subscriptions = GatewaySubscriptions()
  private struct RegistrationWaiter {
    let inbox: Bool?
    let continuation: CheckedContinuation<Void, Never>
  }
  private var registrationWaiters: [String: [RegistrationWaiter]] = [:]
  private var followVersions: [Bool: Int] = [:]
  private var cleanupTasks: [String: Task<Void, Never>] = [:]
  private var challenge: Data?
  private var challengeWaiter: CheckedContinuation<Data, Error>?
  private var authenticated = false
  private var connectionGeneration = 0
  private var connectionLease: GatewayConnectionLease?
  private var connectionScope: PhoneCacheScope?
  private var authenticatedPublication: AuthenticatedGatewaySession?

  private let pairingAccepted: (@Sendable () async -> Void)?
  private let productBatchWaiting: (@Sendable () -> Void)?
  private let commands: JournaledGatewayCommands?
  private var commandBinding: JournaledGatewayCommands.Binding?
  private var commandBindingError: (any Error)?
  public init(journal: PhoneCommandJournal? = nil) {
    commands = journal.map { JournaledGatewayCommands(journal: $0) }
    pairingAccepted = nil
    productBatchWaiting = nil
  }
  /// Internal ordering seam: the production initializer never installs this observer.
  init(pairingAccepted: @escaping @Sendable () async -> Void) {
    commands = nil
    self.pairingAccepted = pairingAccepted
    productBatchWaiting = nil
  }
  /// Ordering observation only; production never holds or alters transport data.
  init(productBatchWaiting: @escaping @Sendable () -> Void) {
    commands = nil
    pairingAccepted = nil
    self.productBatchWaiting = productBatchWaiting
  }

  public func connect(address: String, credential: String, instance: String) async throws {
    _ = try await connectWithLease(address: address, credential: credential, instance: instance)
  }
  public func connectWithLease(address: String, credential: String, instance: String) async throws
    -> GatewayConnectionLease
  {
    disconnect()
    let generation = connectionGeneration
    try await awaitProductDrain()
    guard generation == connectionGeneration else { throw NessaGatewayError.disconnected }
    let lease = GatewayConnectionLease()
    connectionLease = lease
    do {
      try await openConnection(
        address: address, credential: credential, instance: instance, generation: generation)
      guard generation == connectionGeneration else { throw NessaGatewayError.disconnected }
      if let commands, let scope = connectionScope {
        do {
          let binding = try await commands.bind(scope: scope, connection: lease)
          guard generation == connectionGeneration else { throw NessaGatewayError.disconnected }
          commandBinding = binding
        } catch {
          guard generation == connectionGeneration else { throw NessaGatewayError.disconnected }
          commandBindingError = error
        }
      }
      return lease
    } catch {
      if generation == connectionGeneration { close(error) }
      throw error
    }
  }
  /// Composition passes the child of the same retained native parent. Historical
  /// adoption and bootstrap authentication cannot manufacture this publication.
  /// `uploads` is the gateway address attachments are sent to; with none,
  /// attachments are not offered on this connection.
  func connectProduct(
    _ exchange: any GatewayProductExchange, uploads address: String?, scope: PhoneCacheScope
  ) async throws -> GatewayConnectionLease {
    disconnect()
    let generation = connectionGeneration
    do {
      try await awaitProductDrain()
      guard generation == connectionGeneration else { throw NessaGatewayError.disconnected }
      product = exchange
      let lease = GatewayConnectionLease()
      connectionLease = lease
      let ready = try JSONDecoder().decode(GatewayReadyDTO.self, from: await exchange.ready())
      guard generation == connectionGeneration else { throw NessaGatewayError.disconnected }
      authenticatedPublication = .init(connection: lease, snapshot: ready.snapshot)
      authenticated = true
      connectionScope = scope
      imageCache = AttachmentImageCache(scope: scope.key)
      if let address { try configureUploadEndpoint(address) } else { uploadURL = nil }
      if let commands {
        do {
          let binding = try await commands.bind(scope: scope, connection: lease)
          guard generation == connectionGeneration else { throw NessaGatewayError.disconnected }
          commandBinding = binding
        } catch {
          guard generation == connectionGeneration else { throw NessaGatewayError.disconnected }
          commandBindingError = error
        }
      }
      reader = Task { [weak self, exchange] in
        do {
          while !Task.isCancelled {
            let batch = try await exchange.events()
            await self?.receiveProduct(batch, generation: generation)
          }
        } catch { await self?.productFailed(error, generation: generation) }
      }
      return lease
    } catch {
      if generation == connectionGeneration { close(error) }
      // If admission never transferred this child, its physical owner still drains.
      let cleanup = await beginProductDrain(exchange).value
      if let failure = cleanup.failure {
        throw GatewayProductConnectionFailure(underlying: error, cleanup: failure)
      }
      throw error
    }
  }
  public func retire(_ lease: GatewayConnectionLease) {
    if connectionLease == lease { close(NessaGatewayError.disconnected) }
  }
  public func authenticatedSession(for lease: GatewayConnectionLease) throws
    -> AuthenticatedGatewaySession
  {
    try requireConnection()
    guard connectionLease == lease, let publication = authenticatedPublication,
      publication.connection == lease
    else { throw NessaGatewayError.disconnected }
    return publication
  }
  public func createDevice(on lease: GatewayConnectionLease) async throws
    -> GatewayPairingReceipt<GatewayPairingCreated>
  {
    let (source, value): (AuthenticatedGatewaySession, GatewayPairingCreatedDTO) =
      try await pairing(
        "pairing.create", params: PairingCreate(enrollee: .device), schema: "PairingCreateParams",
        on: lease)
    return .init(source: source, value: value.value)
  }
  public func pairingStatus(_ invitation: Data, on lease: GatewayConnectionLease) async throws
    -> GatewayPairingReceipt<GatewayPairingStatus>
  {
    let (source, value): (AuthenticatedGatewaySession, GatewayPairingStatusDTO) = try await pairing(
      "pairing.status", params: PairingInvitation(invitationId: Array(invitation)),
      schema: "PairingInvitationParams", on: lease)
    return .init(source: source, value: value.value)
  }
  public func approvePairing(_ invitation: Data, deviceKey: Data, on lease: GatewayConnectionLease)
    async throws
    -> GatewayPairingReceipt<GatewayPairingApproval>
  {
    let (source, value): (AuthenticatedGatewaySession, GatewayPairingApprovalDTO) =
      try await pairing(
        "pairing.approve",
        params: PairingApprove(invitationId: Array(invitation), deviceKey: Array(deviceKey)),
        schema: "PairingApproveParams", on: lease)
    return .init(source: source, value: value.value)
  }
  public func cancelPairing(_ invitation: Data, on lease: GatewayConnectionLease) async throws
    -> GatewayPairingReceipt<GatewayPairingStatus>
  {
    let (source, value): (AuthenticatedGatewaySession, GatewayPairingStatusDTO) = try await pairing(
      "pairing.cancel", params: PairingInvitation(invitationId: Array(invitation)),
      schema: "PairingInvitationParams", on: lease)
    return .init(source: source, value: value.value)
  }
  public func pendingPairings(on lease: GatewayConnectionLease) async throws
    -> GatewayPairingReceipt<[GatewayPairingStatus]>
  {
    let (source, value): (AuthenticatedGatewaySession, GatewayPairingPendingDTO) =
      try await pairing(
        "pairing.pending", params: Empty(), schema: nil, on: lease)
    return .init(source: source, value: value.values)
  }
  func pairing<P: Encodable, R: Decodable>(
    _ method: String, params: P, schema: String?, on lease: GatewayConnectionLease
  ) async throws -> (AuthenticatedGatewaySession, R) {
    let source = try authenticatedSession(for: lease)
    guard let originalSocket = socket else { throw NessaGatewayError.disconnected }
    if let schema { try validateGatewayWire(JSONEncoder().encode(params), named: schema) }
    let value: R = try await request(
      method, params: params, expectedSocket: originalSocket, pairingSource: source)
    return (source, value)
  }
  private struct PairingCreate: Encodable { let enrollee: GatewayPairingEnrollee }
  private struct PairingInvitation: Encodable { let invitationId: [UInt8] }
  private struct PairingApprove: Encodable {
    let invitationId: [UInt8]
    let deviceKey: [UInt8]
  }

  private func openConnection(
    address: String, credential: String, instance: String, generation: Int
  ) async throws {
    guard let url = URL(string: address), ["ws", "wss"].contains(url.scheme), url.host != nil,
      url.path == "/session", url.user == nil, url.password == nil, url.query == nil
    else {
      throw NessaGatewayError.invalidAddress
    }
    guard url.scheme == "wss" || ["127.0.0.1", "[::1]", "::1"].contains(url.host ?? "") else {
      throw NessaGatewayError.invalidAddress
    }
    try configureUploadEndpoint(address)
    imageCache = AttachmentImageCache(scope: address + "|" + instance + "|" + credential)
    let task = URLSession.shared.webSocketTask(with: url)
    task.maximumMessageSize = 1_048_576
    socket = task
    task.resume()
    reader = Task { [weak self] in
      do {
        while !Task.isCancelled {
          let message = try await task.receive()
          await self?.receive(message, task: task)
        }
      } catch { await self?.transportFailed(task: task, error: error) }
    }
    let challengeData = try await waitForChallenge()
    guard generation == connectionGeneration, socket === task else {
      throw NessaGatewayError.disconnected
    }
    let challenge = try JSONDecoder().decode(Challenge.self, from: challengeData)
    guard challenge.minVersion <= 1, challenge.maxVersion >= 1,
      challenge.expiresAt > Date().timeIntervalSince1970
    else { throw NessaGatewayError.incompatibleProtocol }
    let params = Authenticate(
      minVersion: 1, maxVersion: 1, nonce: challenge.nonce,
      credential: credential, client: .init(id: "nessa-ios"),
      surface: .init(kind: "panel", instance: instance))
    let result: GatewayReadyDTO = try await request(
      "session.authenticate", params: params, expectedSocket: task)
    guard generation == connectionGeneration else { throw NessaGatewayError.disconnected }
    guard let lease = connectionLease else { throw NessaGatewayError.disconnected }
    authenticatedPublication = AuthenticatedGatewaySession(
      connection: lease, snapshot: result.snapshot)
    authenticated = true
    connectionScope = PhoneCacheScope(address: address, credential: credential, instance: instance)
  }
  private func configureUploadEndpoint(_ address: String) throws {
    guard let url = URL(string: address), let scheme = url.scheme,
      ["ws", "wss"].contains(scheme), url.host != nil, url.path == "/session",
      url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
      scheme == "wss" || ["127.0.0.1", "[::1]", "::1"].contains(url.host ?? ""),
      var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    else { throw NessaGatewayError.invalidAddress }
    components.scheme = scheme == "wss" ? "https" : "http"
    components.path = "/attachments"
    uploadURL = components.url
  }

  public func list() async throws -> NessaConversationList {
    try requireConnection()
    return try await request("conversation.list", params: Empty())
  }
  public func listArchived() async throws -> NessaConversationList {
    try requireConnection()
    struct Archived: Encodable { let archived = true }
    return try await request("conversation.list", params: Archived())
  }
  public func setArchived(_ archived: Bool, conversationID: String) async throws {
    try requireConnection()
    struct Archive: Encodable {
      let conversationId: String
      let requestId: String
    }
    let _: Ignored = try await request(
      archived ? "conversation.archive" : "conversation.unarchive",
      params: Archive(
        conversationId: conversationID, requestId: UUID().uuidString.lowercased()))
  }
  public func waitingReviews() -> AsyncStream<WaitingReviews> {
    let (stream, continuation) = AsyncStream<WaitingReviews>.makeStream(
      bufferingPolicy: .bufferingNewest(1))
    // Without a connection there is nothing to announce; the stream ends at once.
    guard authenticated else {
      continuation.finish()
      return stream
    }
    let id = UUID()
    reviewListeners[id] = continuation
    continuation.onTermination = { _ in Task { await self.stopListening(id) } }
    if let latestReviews { continuation.yield(latestReviews) }
    return stream
  }
  private func stopListening(_ id: UUID) { reviewListeners.removeValue(forKey: id) }
  /// Takes a `permission.reviewWaiting` announcement, checked against the gateway's
  /// PermissionReviewWaiting, as the new latest. False for any other event.
  private func receiveReviews(_ name: String, payload: Data) throws -> Bool {
    guard name == "permission.reviewWaiting" else { return false }
    try validateGatewayWire(payload, named: "PermissionReviewWaiting")
    let reviews = try JSONDecoder().decode(WaitingReviews.self, from: payload)
    latestReviews = reviews
    for listener in reviewListeners.values { listener.yield(reviews) }
    return true
  }
  private func endReviews() {
    latestReviews = nil
    let listeners = reviewListeners.values
    reviewListeners.removeAll()
    for listener in listeners { listener.finish() }
  }
  public func channels() async throws -> [NessaChannel] {
    try requireConnection()
    struct After: Encodable { let after: String? }
    var channels: [NessaChannel] = []
    var after: String?
    var seen: Set<String> = []
    // Pages follow the cursor until the gateway says the list is complete. An unfinished
    // list must name where to go on, and a cursor seen before would go round for ever: both
    // are a broken answer, not a short list.
    while true {
      let params = After(after: after)
      try validateGatewayWire(JSONEncoder().encode(params), named: "ChannelListParams")
      let dto: GatewayChannelPageDTO = try await request("channel.list", params: params)
      let page = dto.page
      channels += page.channels
      if page.complete { return channels }
      guard let cursor = page.cursor, seen.insert(cursor).inserted else {
        throw NessaGatewayError.invalidFrame
      }
      after = cursor
    }
  }
  public func agents() async throws -> [AgentProfile] {
    try requireConnection()
    let result: GatewayAgentListDTO = try await request("agents.list", params: Empty())
    return result.agents.map(\.profile)
  }
  public func read(_ id: String) async throws -> NessaConversationView {
    try requireConnection()
    return try await request("conversation.read", params: ConversationID(conversationId: id))
  }
  public func create(agent: String? = nil, model: String? = nil) async throws -> String {
    try await create(
      .init(
        requestID: UUID().uuidString.lowercased(),
        conversationID: UUID().uuidString.lowercased(), agent: agent, model: model))
  }
  public func create(_ intent: PreparedConversationCommand.Creation) async throws -> String {
    try requireConnection()
    if let commands {
      let binding = try currentCommandBinding()
      _ = try await commands.execute(.create(intent), binding: binding, transport: self)
      return intent.conversationID
    }
    let _: Created = try await request(
      "conversation.create",
      params: Create(
        conversationId: intent.conversationID, requestId: intent.requestID,
        agent: intent.agent, model: intent.model))
    return intent.conversationID
  }
  public func pendingCommands() async throws -> [PreparedConversationCommand] {
    try requireConnection()
    guard let commands else { return [] }
    let binding = try currentCommandBinding()
    let result = try await commands.pending(binding)
    try requireCommandConnection(binding.connection, scope: binding.scope)
    return result
  }
  public func checkCommand(_ requestID: String) async throws -> ResolvedConversationCommand? {
    guard let commands else { throw NessaGatewayError.incompatibleProtocol }
    return try await commands.check(requestID, binding: currentCommandBinding(), transport: self)
  }
  public func retryCommand(_ requestID: String) async throws -> ResolvedConversationCommand {
    guard let commands else { throw NessaGatewayError.incompatibleProtocol }
    return try await commands.retry(requestID, binding: currentCommandBinding(), transport: self)
  }
  private func currentCommandBinding() throws -> JournaledGatewayCommands.Binding {
    try requireConnection()
    if let commandBindingError { throw commandBindingError }
    guard let binding = commandBinding else { throw PhoneCommandStoreError.unavailable }
    try requireCommandConnection(binding.connection, scope: binding.scope)
    return binding
  }
  public func dispatch(
    _ command: PreparedConversationCommand, connection: GatewayConnectionLease,
    scope: PhoneCacheScope
  ) async throws -> ConversationCommandAcknowledgment {
    try requireCommandConnection(connection, scope: scope)
    try command.validate()
    let acknowledgment: ConversationCommandAcknowledgment
    do {
      switch command {
      case .create(let value):
        let result: Created = try await request(
          "conversation.create",
          params: Create(
            conversationId: value.conversationID, requestId: value.requestID,
            agent: value.agent, model: value.model))
        acknowledgment = .created(result.conversationId)
      case .submit(let value):
        struct Submission: Decodable {
          enum Disposition: String, Decodable { case queued, injected, settled }
          let executionId: String
          let disposition: Disposition
        }
        let result: Submission = try await request(
          "conversation.send",
          params: Send(
            conversationId: value.conversationID, requestId: value.requestID,
            executionId: value.executionID, text: value.text, attachments: value.images, files: []))
        acknowledgment = .submitted(result.executionId)
      }
    } catch {
      let original = error
      guard let error = (error as? GatewayProductRejection)?.behavior ?? error as? NessaGatewayError
      else { throw original }
      // These codes are audited before effects. The journal additionally proves
      // this is the sole durable dispatch attempt, not a later uncertain retry.
      switch (command, error) {
      case (.create, .modelUnavailable):
        throw ConversationCommandRefusal(command: command, reason: .modelUnavailable)
      case (.create, .agentNotConfigured):
        throw ConversationCommandRefusal(command: command, reason: .agentNotConfigured)
      case (.submit, .imageInputUnsupported):
        throw ConversationCommandRefusal(command: command, reason: .imagesUnsupported)
      default: throw original
      }
    }
    // This is a factual acknowledgment of the original admitted command. The
    // journal owns its publication; navigation/lease retirement fences UI later.
    guard acknowledgment.validates(command) else { throw NessaGatewayError.invalidFrame }
    return acknowledgment
  }
  public func receipt(
    _ command: PreparedConversationCommand, connection: GatewayConnectionLease,
    scope: PhoneCacheScope
  ) async throws -> ConversationCommandReceipt {
    try requireCommandConnection(connection, scope: scope)
    try command.validate()
    struct Lookup: Encodable {
      let conversationId: String
      let requestId: String
      let operation: String
      let executionId: String?
      let text: String?
      let attachments: [NessaImageAttachment]?
      let files: [String]?
      let agent: String?
      let model: String?
    }
    let lookup: Lookup
    switch command {
    case .create(let value):
      lookup = Lookup(
        conversationId: value.conversationID, requestId: value.requestID,
        operation: "create", executionId: nil, text: nil, attachments: nil, files: nil,
        agent: value.agent, model: value.model)
    case .submit(let value):
      lookup = Lookup(
        conversationId: value.conversationID, requestId: value.requestID,
        operation: "submit", executionId: value.executionID, text: value.text,
        attachments: value.images, files: [], agent: nil, model: nil)
    }
    let result: ConversationCommandReceipt = try await request(
      "conversation.receipt", params: lookup)
    try requireCommandConnection(connection, scope: scope)
    do { _ = try result.acknowledgment(for: command) } catch {
      throw NessaGatewayError.invalidFrame
    }
    return result
  }
  private func requireCommandConnection(
    _ connection: GatewayConnectionLease, scope: PhoneCacheScope
  ) throws {
    try requireConnection()
    guard connectionLease == connection, connectionScope == scope else {
      throw NessaGatewayError.disconnected
    }
  }
  public func delete(_ conversationID: String) async throws {
    try requireConnection()
    struct Delete: Encodable {
      let conversationId: String
      let requestId: String
    }
    let _: Ignored = try await request(
      "conversation.delete",
      params: Delete(conversationId: conversationID, requestId: UUID().uuidString))
  }
  @discardableResult
  public func send(_ text: String, attachments: [DraftAttachment], conversationID: String)
    async throws -> String
  {
    try await send(
      text, attachments: attachments, conversationID: conversationID,
      identity: MessageCommandIdentity(), replyTo: nil)
  }
  public func send(
    _ text: String, attachments: [DraftAttachment], conversationID: String,
    identity: MessageCommandIdentity, replyTo: String?
  ) async throws -> String {
    try requireConnection()
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty,
      text.utf8.count <= 8192
    else {
      throw NessaGatewayError.rejected("Messages must contain text and fit within 8 KiB.")
    }
    try attachmentPolicy.validate(attachments)
    let generation = connectionGeneration
    let binding = commands == nil ? nil : try currentCommandBinding()
    if let binding,
      let existing = try await commands?.pending(binding).first(where: {
        if case .submit = $0 {
          return $0.conversationID == conversationID && $0.requestID != identity.requestID
        }
        return false
      })
    {
      throw CommandAdmissionBlocked(requestID: existing.requestID)
    }
    guard generation == connectionGeneration, !Task.isCancelled else {
      throw NessaGatewayError.disconnected
    }
    var images: [NessaImageAttachment] = []
    for attachment in attachments {
      images.append(try await upload(attachment, conversationID: conversationID))
      guard generation == connectionGeneration, !Task.isCancelled else {
        throw NessaGatewayError.disconnected
      }
    }
    guard images.reduce(0, { $0 + $1.size }) <= 10 * 1024 * 1024 else {
      throw NessaGatewayError.rejected("Uploaded images must total at most 10 MB.")
    }
    if let commands, let binding {
      let prepared = PreparedConversationCommand.submit(
        .init(
          requestID: identity.requestID,
          conversationID: conversationID, executionID: identity.executionID, text: text,
          images: images, replyTo: replyTo))
      _ = try await commands.execute(prepared, binding: binding, transport: self)
      return identity.executionID
    }
    let _: Ignored = try await request(
      "conversation.send",
      params: Send(
        conversationId: conversationID,
        requestId: identity.requestID, executionId: identity.executionID, text: text,
        attachments: images, files: []))
    return identity.executionID
  }
  private func upload(_ attachment: DraftAttachment, conversationID: String) async throws
    -> NessaImageAttachment
  {
    struct Begin: Encodable {
      let conversationId: String
      let requestId: String
      let digest: String
      let mimeType: String
      let size: Int
    }
    struct Ticket: Decodable {
      let state: String
      let ticket: String?
      let expiresAtMs: Double?
      let digest: String?
      let mimeType: String?
      let size: Int?
    }
    let currentGeneration = connectionGeneration
    guard let uploadEndpoint = uploadURL else { throw NessaGatewayError.disconnected }
    let digest =
      "sha256:" + SHA256.hash(data: attachment.data).map { String(format: "%02x", $0) }.joined()
    let result: Ticket = try await request(
      "attachment.begin",
      params: Begin(
        conversationId: conversationID, requestId: UUID().uuidString.lowercased(), digest: digest,
        mimeType: attachment.mimeType, size: attachment.data.count))
    guard currentGeneration == connectionGeneration else { throw NessaGatewayError.disconnected }
    let image: NessaImageAttachment
    if result.state == "stored", let digest = result.digest, let mimeType = result.mimeType,
      let size = result.size
    {
      image = NessaImageAttachment(digest: digest, mimeType: mimeType, size: size)
    } else if result.state == "upload_required", let ticket = result.ticket,
      let expiry = result.expiresAtMs, expiry > Date().timeIntervalSince1970 * 1000
    {
      image = try await AttachmentUploadTransport.put(
        attachment, ticket: ticket, url: uploadEndpoint)
    } else {
      throw NessaGatewayError.invalidFrame
    }
    guard currentGeneration == connectionGeneration, !Task.isCancelled else {
      throw NessaGatewayError.disconnected
    }
    guard ["image/png", "image/jpeg", "image/gif", "image/webp"].contains(image.mimeType),
      image.size > 0, image.size <= 5 * 1024 * 1024,
      image.digest.hasPrefix("sha256:"), image.digest.count == 71
    else { throw NessaGatewayError.invalidFrame }
    guard image.digest == digest, image.size == attachment.data.count,
      image.mimeType == attachment.mimeType
    else { throw NessaGatewayError.invalidFrame }
    await imageCache?.store(attachment.data, digest: image.digest)
    guard currentGeneration == connectionGeneration else { throw NessaGatewayError.disconnected }
    return image
  }
  public func answer(
    _ permission: NessaPermission, option: NessaPermission.Option, conversationID: String
  ) async throws {
    try requireConnection()
    let _: Ignored = try await request(
      "conversation.answer",
      params: Answer(
        conversationId: conversationID,
        requestId: UUID().uuidString, executionId: permission.executionId,
        permissionId: permission.permissionId, optionId: option.id))
  }
  public func follow(_ conversationID: String?, after: ConversationCursor? = nil) async throws
    -> AsyncThrowingStream<ConversationUpdate, Error>
  {
    try requireConnection()
    let generation = connectionGeneration
    let inbox = conversationID == nil
    followVersions[inbox, default: 0] += 1
    let version = followVersions[inbox]!
    // A newer navigation request wakes obsolete admission waiters immediately.
    for token in Array(registrationWaiters.keys) {
      let obsolete = (registrationWaiters[token] ?? []).filter { $0.inbox == inbox }
      registrationWaiters[token]?.removeAll { $0.inbox == inbox }
      for waiter in obsolete { waiter.continuation.resume() }
    }
    while true {
      try checkFollow(generation: generation, inbox: inbox, version: version)
      if let cleanup = cleanupTasks.values.first {
        await cleanup.value
        continue
      }
      if let previous = subscriptions.replacement(for: conversationID) {
        await cancelSubscription(previous, generation: generation)
        if subscriptions.awaiting(previous) {
          await withCheckedContinuation {
            registrationWaiters[previous, default: []].append(
              RegistrationWaiter(inbox: inbox, continuation: $0))
          }
        }
        continue
      }
      break
    }
    let token = UUID().uuidString
    let stream = try subscriptions.prepare(token, conversationID: conversationID) { [weak self] in
      Task { await self?.cancelSubscription(token, generation: generation) }
    }
    do {
      return try await withTaskCancellationHandler {
        if let conversationID {
          struct Follow: Encodable {
            let conversationId: String
            let after: ConversationCursor?
          }
          let _: Ignored = try await request(
            "conversation.subscribe",
            params: Follow(conversationId: conversationID, after: after), id: token)
        } else {
          let _: Ignored = try await request(
            "conversation.subscribeList", params: Empty(), id: token)
        }
        try checkFollow(generation: generation, inbox: inbox, version: version)
        return stream
      } onCancel: {
        Task { await self.cancelSubscription(token, generation: generation) }
      }
    } catch {
      subscriptions.fail(token, error: error)
      registrationSettled(token)
      throw error
    }
  }
  private func checkFollow(generation: Int, inbox: Bool, version: Int) throws {
    try Task.checkCancellation()
    guard generation == connectionGeneration else { throw NessaGatewayError.disconnected }
    guard followVersions[inbox] == version else { throw CancellationError() }
  }
  private func cancelSubscription(_ token: String, generation: Int) async {
    guard generation == connectionGeneration else { return }
    if let id = subscriptions.cancel(token) { await beginCleanup(id, generation: generation).value }
  }
  private func beginCleanup(_ id: String, generation: Int) -> Task<Void, Never> {
    if let existing = cleanupTasks[id] { return existing }
    let task = Task { await self.stopSubscription(id, generation: generation) }
    cleanupTasks[id] = task
    return task
  }
  private func stopSubscription(_ id: String, generation: Int) async {
    defer { if generation == connectionGeneration { cleanupTasks.removeValue(forKey: id) } }
    guard generation == connectionGeneration, authenticated else { return }
    struct Stop: Encodable { let subscriptionId: String }
    do {
      let _: Ignored = try await request(
        "conversation.unsubscribe", params: Stop(subscriptionId: id))
    } catch {
      let behavior = (error as? GatewayProductRejection)?.behavior ?? error as? NessaGatewayError
      // A terminal publication can retire the remote subscription before cleanup arrives.
      if case .unknownSubscription = behavior { return }
      if generation == connectionGeneration { close(error) }
    }
  }
  private func registrationSettled(_ token: String) {
    for waiter in registrationWaiters.removeValue(forKey: token) ?? [] {
      waiter.continuation.resume()
    }
  }
  public func disconnect() { close(NessaGatewayError.disconnected) }
  private func close(_ error: Error) {
    authenticatedPublication = nil
    connectionLease = nil
    connectionScope = nil
    commandBinding = nil
    commandBindingError = nil
    connectionGeneration += 1
    let waiters = registrationWaiters.values.flatMap { $0 }
    registrationWaiters.removeAll()
    for waiter in waiters { waiter.continuation.resume() }
    followVersions.removeAll()
    for cleanup in cleanupTasks.values { cleanup.cancel() }
    cleanupTasks.removeAll()
    authenticated = false
    reader?.cancel()
    reader = nil
    if let product {
      _ = beginProductDrain(product)
      self.product = nil
    }
    socket?.cancel(with: .goingAway, reason: nil)
    socket = nil
    subscriptions.finishAll(error)
    endReviews()
    failPending(error)
    challenge = nil
  }
  private func requireConnection() throws {
    guard authenticated, product != nil || socket != nil else {
      throw NessaGatewayError.disconnected
    }
  }
  private func awaitProductDrain() async throws {
    while let (id, draining) = productDrains.first {
      var observation = await draining.task.value
      if !observation.released {
        // Retry observation on that same physical owner; no filesystem probe or
        // diagnostic classification can clear its release barrier.
        observation = await draining.exchange.close()
      }
      guard observation.released else {
        throw observation.failure ?? NessaGatewayError.disconnected
      }
      productDrains.removeValue(forKey: id)
    }
  }
  private func beginProductDrain(_ exchange: any GatewayProductExchange)
    -> Task<GatewayProductCloseObservation, Never>
  {
    let id = ObjectIdentifier(exchange)
    if let existing = productDrains[id] { return existing.task }
    exchange.requestClose()
    let task = Task.detached { await exchange.close() }
    productDrains[id] = .init(exchange: exchange, task: task)
    return task
  }
  private func waitForChallenge() async throws -> Data {
    if let challenge { return challenge }
    let generation = connectionGeneration
    return try await withCheckedThrowingContinuation { continuation in
      challengeWaiter = continuation
      Task {
        try? await Task.sleep(for: .seconds(5))
        self.expireChallenge(generation)
      }
    }
  }
  private func expireChallenge(_ generation: Int) {
    guard generation == connectionGeneration else { return }
    challengeWaiter?.resume(throwing: NessaGatewayError.timeout)
    challengeWaiter = nil
  }
  private func request<P: Encodable, R: Decodable>(
    _ method: String, params: P,
    id: String = UUID().uuidString, expectedSocket: URLSessionWebSocketTask? = nil,
    pairingSource: AuthenticatedGatewaySession? = nil, preserveRefusal: Bool = false
  ) async throws -> R {
    if let product, expectedSocket == nil, pairingSource == nil {
      let generation = connectionGeneration
      // Native admission and its ticket are the sole response/deadline owners.
      let response = try await product.request(
        method: method, parameters: JSONEncoder().encode(params))
      let payload = try productPayload(response)
      if generation == connectionGeneration, subscriptions.awaiting(id) {
        do {
          if let stopped = try subscriptions.activate(id, data: payload) {
            _ = beginCleanup(stopped, generation: generation)
          }
          registrationSettled(id)
        } catch {
          subscriptions.fail(id, error: error)
          registrationSettled(id)
          close(error)
          throw error
        }
      }
      return try JSONDecoder().decode(R.self, from: payload)
    }
    guard let socket, expectedSocket == nil || socket === expectedSocket else {
      throw NessaGatewayError.disconnected
    }
    let data = try JSONEncoder().encode(
      Request(type: "req", id: id, method: method, params: params))
    // Before admission cancellation proves no dispatch. After admission the existing
    // response/timeout/close owner completes it, even when the caller is cancelled.
    if pairingSource != nil { try Task.checkCancellation() }
    do {
      let payload: Data = try await withCheckedThrowingContinuation { continuation in
        pending[id] = PendingRequest(
          continuation: continuation, strictEnvelope: pairingSource != nil,
          failure: { code, message, details in
            if preserveRefusal {
              return PhoneSocketRefusal.error(code: code, message: message, details: details)
            }
            if pairingSource != nil, let code, let message {
              return GatewayPairingRejection(code: code, diagnostic: message, details: details)
            }
            return GatewayFailureDTO.failure(code: code, message: message)
          })
        Task {
          do { try await socket.send(.string(String(decoding: data, as: UTF8.self))) } catch {
            self.expire(id, error: error)
          }
        }
        timeouts[id] = Task {
          do { try await Task.sleep(for: .seconds(30)) } catch { return }
          self.expire(id, error: NessaGatewayError.timeout)
        }
      }
      // The waiter has settled. Testing can hold this ordering before decode/publication.
      if pairingSource != nil, let pairingAccepted { await pairingAccepted() }
      // No current-lease or cancellation fence: this is an accepted historical receipt.
      return try JSONDecoder().decode(R.self, from: payload)
    } catch {
      if let pairingSource {
        // Wire grammar has one application failure; transport and owner codes stay intact.
        let underlying: any Error = error is DecodingError ? NessaGatewayError.invalidFrame : error
        throw GatewayPairingOperationFailure(source: pairingSource, underlying: underlying)
      }
      throw error
    }
  }
  private func productPayload(_ data: Data) throws -> Data {
    // Rust validated the canonical envelope and correlated its UInt64 transport
    // ID. Swift decodes only the application payload and published failure code.
    guard let frame = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      let ok = frame["ok"] as? Bool
    else { throw NessaGatewayError.invalidFrame }
    if ok {
      guard let payload = frame["payload"] else { throw NessaGatewayError.invalidFrame }
      return try JSONSerialization.data(withJSONObject: payload, options: .fragmentsAllowed)
    }
    guard let error = frame["error"] as? [String: Any],
      let code = error["code"] as? String, let message = error["message"] as? String
    else { throw NessaGatewayError.invalidFrame }
    let details = try error["details"].map {
      try JSONSerialization.data(withJSONObject: $0, options: .fragmentsAllowed)
    }
    throw GatewayProductRejection(
      code: code, diagnostic: message, details: details,
      behavior: GatewayFailureDTO.failure(code: code, message: message))
  }
  private func receiveProduct(_ batch: [Data], generation: Int) async {
    do {
      // One native batch stays held here if event capture wins the scheduling
      // race with registration completion. Submit/completion run independently.
      for token in subscriptions.registrations {
        guard generation == connectionGeneration else { return }
        if subscriptions.awaiting(token) {
          await withCheckedContinuation {
            registrationWaiters[token, default: []].append(
              RegistrationWaiter(inbox: nil, continuation: $0))
            productBatchWaiting?()
          }
        }
      }
      guard generation == connectionGeneration else { return }
      for data in batch {
        guard let frame = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let name = frame["event"] as? String, let payload = frame["payload"]
        else { throw NessaGatewayError.invalidFrame }
        let bytes = try JSONSerialization.data(withJSONObject: payload, options: .fragmentsAllowed)
        if try receiveReviews(name, payload: bytes) { continue }
        if let stopped = subscriptions.receive(name, payload: bytes) {
          _ = beginCleanup(stopped, generation: generation)
        }
      }
    } catch { if generation == connectionGeneration { close(error) } }
  }
  private func productFailed(_ error: Error, generation: Int) {
    if generation == connectionGeneration { close(error) }
  }
  private func expire(_ id: String, error: Error) {
    timeouts.removeValue(forKey: id)?.cancel()
    let registration = subscriptions.awaiting(id)
    subscriptions.fail(id, error: error)
    registrationSettled(id)
    pending.removeValue(forKey: id)?.continuation.resume(throwing: error)
    // A lost registration answer may leave an unnamed remote watcher. Close its owner socket.
    if registration { disconnect() }
  }
  private func receive(_ message: URLSessionWebSocketTask.Message, task: URLSessionWebSocketTask) {
    guard socket === task else { return }
    let data: Data
    switch message {
    case .string(let text): data = Data(text.utf8)
    case .data(let bytes): data = bytes
    @unknown default: return
    }
    do {
      let object: Any
      do { object = try JSONSerialization.jsonObject(with: data) } catch {
        throw NessaGatewayError.invalidFrame
      }
      guard let frame = object as? [String: Any] else { throw NessaGatewayError.invalidFrame }
      if pending.values.contains(where: { $0.strictEnvelope }) {
        guard let kind = frame["type"] as? String, kind == "res" || kind == "event" else {
          throw NessaGatewayError.invalidFrame
        }
      }
      if frame["type"] as? String == "res" {
        guard let id = frame["id"] as? String, !id.isEmpty else {
          throw NessaGatewayError.invalidFrame
        }
      }
      let strict: GatewayPairingEnvelope?
      if let id = frame["id"] as? String, pending[id]?.strictEnvelope == true {
        strict = try JSONDecoder().decode(GatewayPairingEnvelope.self, from: data)
      } else {
        strict = nil
      }
      if frame["type"] as? String == "event", frame["event"] as? String == "session.challenge",
        let payload = frame["payload"]
      {
        let bytes = try JSONSerialization.data(withJSONObject: payload)
        challenge = bytes
        challengeWaiter?.resume(returning: bytes)
        challengeWaiter = nil
      } else if frame["type"] as? String == "res", let id = frame["id"] as? String,
        let waiter = pending.removeValue(forKey: id)
      {
        timeouts.removeValue(forKey: id)?.cancel()
        let registration = subscriptions.awaiting(id)
        do {
          if frame["ok"] as? Bool == true {
            let payload = try JSONSerialization.data(
              withJSONObject: frame["payload"] ?? [:], options: .fragmentsAllowed)
            if subscriptions.awaiting(id),
              let stopped = try subscriptions.activate(id, data: payload)
            {
              let generation = connectionGeneration
              _ = beginCleanup(stopped, generation: generation)
            }
            registrationSettled(id)
            waiter.continuation.resume(returning: payload)
          } else {
            let error = frame["error"] as? [String: Any]
            let details = try error?["details"].map {
              try JSONSerialization.data(withJSONObject: $0, options: .fragmentsAllowed)
            }
            let failure = waiter.failure(
              strict?.rejection?.code ?? error?["code"] as? String,
              strict?.rejection?.diagnostic ?? error?["message"] as? String, details)
            subscriptions.fail(id, error: failure)
            registrationSettled(id)
            waiter.continuation.resume(throwing: failure)
          }
        } catch {
          subscriptions.fail(id, error: error)
          registrationSettled(id)
          waiter.continuation.resume(throwing: error)
          if registration { close(error) }
        }
      } else if frame["type"] as? String == "event", let name = frame["event"] as? String,
        let payload = frame["payload"]
      {
        let bytes = try JSONSerialization.data(withJSONObject: payload)
        if try receiveReviews(name, payload: bytes) { return }
        if let stopped = subscriptions.receive(name, payload: bytes) {
          let generation = connectionGeneration
          _ = beginCleanup(stopped, generation: generation)
        }
      }
    } catch { close(error) }
  }
  private func transportFailed(task: URLSessionWebSocketTask, error: Error) {
    guard socket === task else { return }
    // Preserve certificate and transport outcomes for the recovery policy.
    close((error as? URLError) ?? NessaGatewayError.disconnected)
  }
  private func failPending(_ error: Error) {
    for timeout in timeouts.values { timeout.cancel() }
    timeouts.removeAll()
    for waiter in pending.values { waiter.continuation.resume(throwing: error) }
    pending.removeAll()
    challengeWaiter?.resume(throwing: error)
    challengeWaiter = nil
  }
  public func send(_ intent: PhoneSendIntent) async -> PhoneSendAnswer {
    struct Body: Encodable {
      let conversationId: String
      let requestId: String
      let executionId: String
      let text: String
      let attachments: [NessaImageAttachment]
      let files: [String]
    }
    let payload = await phoneDecode(
      "conversation.send",
      params: Body(
        conversationId: intent.conversationID, requestId: intent.commandID,
        executionId: intent.turnID, text: intent.text, attachments: intent.images, files: []),
      as: PhoneWireReceipt.self)
    return phoneSendAnswer(payload, turnID: intent.turnID)
  }
  public func lookup(_ intent: PhoneSendIntent) async -> PhoneLookupAnswer {
    struct Body: Encodable {
      let conversationId: String
      let requestId: String
      let operation: String
      let executionId: String
      let text: String
      let attachments: [NessaImageAttachment]
      let files: [String]
    }
    let payload = await phoneDecode(
      "conversation.receipt",
      params: Body(
        conversationId: intent.conversationID, requestId: intent.commandID, operation: "submit",
        executionId: intent.turnID, text: intent.text, attachments: intent.images, files: []),
      as: PhoneWireLookup.self)
    return phoneLookupAnswer(payload, requestID: intent.commandID)
  }
  public func uploadPhoneImage(_ attachment: DraftAttachment, conversationID: String) async throws
    -> NessaImageAttachment
  {
    try await upload(attachment, conversationID: conversationID)
  }
  public func phoneStop(conversationID: String, requestID: String, executionID: String) async
    -> PhoneSendAnswer
  {
    struct Body: Encodable {
      let conversationId: String
      let requestId: String
      let executionId: String
    }
    let payload = await phoneDecode(
      "conversation.stop",
      params: Body(
        conversationId: conversationID, requestId: requestID, executionId: executionID),
      as: PhoneWireReceipt.self)
    return phoneSendAnswer(payload, turnID: executionID)
  }
  public func phoneLookupStop(conversationID: String, requestID: String, executionID: String) async
    -> PhoneLookupAnswer
  {
    struct Body: Encodable {
      let conversationId: String
      let requestId: String
      let operation: String
      let executionId: String
    }
    let payload = await phoneDecode(
      "conversation.receipt",
      params: Body(
        conversationId: conversationID, requestId: requestID, operation: "stop",
        executionId: executionID),
      as: PhoneWireLookup.self)
    return phoneLookupAnswer(payload, requestID: requestID)
  }
  private struct PhoneWireReceipt: Decodable {
    let executionId: String
    let disposition: String
  }
  private struct PhoneWireLookup: Decodable {
    let found: Bool
    let requestId: String
    let stage: String?
    let outcome: String?
  }
  private enum PhoneDecoded<Value> {
    case value(Value)
    case refused(String)
    case lost
    case broken
  }
  private func phoneDecode<P: Encodable, R: Decodable>(
    _ method: String, params: P, as type: R.Type
  ) async -> PhoneDecoded<R> {
    do {
      _ = type
      return .value(try await request(method, params: params, preserveRefusal: true))
    } catch let rejection as GatewayProductRejection {
      return rejection.code.isEmpty ? .broken : .refused(rejection.code)
    } catch is DecodingError {
      return .broken
    } catch let error as NessaGatewayError {
      switch error {
      case .revoked(let code): return .refused(code)
      case .invalidFrame: return .broken
      default: return .lost
      }
    } catch {
      return .lost
    }
  }
  private func phoneSendAnswer(
    _ payload: PhoneDecoded<PhoneWireReceipt>, turnID: String
  ) -> PhoneSendAnswer {
    switch payload {
    case .lost: return .lost
    case .broken: return .broken
    case .refused(let code): return .refused(code)
    case .value(let receipt):
      guard receipt.executionId == turnID else { return .broken }
      switch receipt.disposition {
      case "queued": return .receipt(.queued)
      case "injected": return .receipt(.injected)
      case "settled": return .receipt(.settled)
      default: return .broken
      }
    }
  }
  private func phoneLookupAnswer(
    _ payload: PhoneDecoded<PhoneWireLookup>, requestID: String
  ) -> PhoneLookupAnswer {
    switch payload {
    case .lost: return .lost
    case .broken: return .broken
    case .refused(let code): return .refused(code)
    case .value(let result):
      guard result.requestId == requestID else { return .broken }
      if !result.found {
        return result.stage == nil && result.outcome == nil ? .notFound : .broken
      }
      guard let stage = result.stage else { return .broken }
      return .found(stage: stage, effect: result.outcome)
    }
  }
  private struct Empty: Encodable {}
  private struct Ignored: Decodable {}
  private struct Challenge: Decodable {
    let minVersion: Int
    let maxVersion: Int
    let nonce: String
    let expiresAt: Double
  }
  private struct Authenticate: Encodable {
    let minVersion: Int
    let maxVersion: Int
    let nonce: String
    let credential: String
    let client: Client
    let surface: Surface
    struct Client: Encodable { let id: String }
    struct Surface: Encodable {
      let kind: String
      let instance: String
    }
  }
  private struct Request<P: Encodable>: Encodable {
    let type: String
    let id: String
    let method: String
    let params: P
  }
  private struct ConversationID: Encodable { let conversationId: String }
  private struct Create: Encodable {
    let conversationId: String
    let requestId: String
    let agent: String?
    let model: String?
  }
  private struct Created: Decodable { let conversationId: String }
  private struct Send: Encodable {
    let conversationId: String
    let requestId: String
    let executionId: String
    let text: String
    let attachments: [NessaImageAttachment]
    let files: [String]
  }
  private struct Answer: Encodable {
    let conversationId: String
    let requestId: String
    let executionId: String
    let permissionId: String
    let optionId: String
  }
}

extension NessaGatewayClient: PhoneProductTransport {}

extension NessaGatewayClient: LinkedProductConnecting {
  /// The paired Mac's product session, over its native link. Attachments go
  /// over HTTP to the gateway, which the link does not carry, so none are
  /// offered here.
  func connectLinked(_ exchange: any GatewayProductExchange, scope: PhoneCacheScope)
    async throws -> GatewayConnectionLease
  {
    try await connectProduct(exchange, uploads: nil, scope: scope)
  }
  func drainLinked() async throws { try await awaitProductDrain() }
}
