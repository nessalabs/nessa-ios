import CryptoKit
import Foundation

/// Native implementation of Nessa's product v1 req/res protocol. Commands are never replayed.
public actor NessaGatewayClient: MessagingRepository, AgentDirectory, ConversationFollowing {
  public nonisolated var attachmentPolicy: AttachmentPolicy { .nessa }
  private var imageCache: AttachmentImageCache?
  public func imageData(for attachment: NessaImageAttachment) async throws -> Data? {
    try requireConnection()
    return await imageCache?.read(attachment.digest)
  }
  private var uploadURL: URL?
  private var socket: URLSessionWebSocketTask?
  private var reader: Task<Void, Never>?
  private var pending: [String: CheckedContinuation<Data, Error>] = [:]
  private var timeouts: [String: Task<Void, Never>] = [:]
  private var subscriptions = GatewaySubscriptions()
  private struct RegistrationWaiter {
    let inbox: Bool
    let continuation: CheckedContinuation<Void, Never>
  }
  private var registrationWaiters: [String: [RegistrationWaiter]] = [:]
  private var followVersions: [Bool: Int] = [:]
  private var cleanupTasks: [String: Task<Void, Never>] = [:]
  private var challenge: Data?
  private var challengeWaiter: CheckedContinuation<Data, Error>?
  private var authenticated = false
  private var connectionGeneration = 0

  public init() {}

  public func connect(address: String, credential: String, instance: String) async throws {
    disconnect()
    let generation = connectionGeneration
    guard let url = URL(string: address), ["ws", "wss"].contains(url.scheme), url.host != nil,
      url.path == "/session", url.user == nil, url.password == nil, url.query == nil
    else {
      throw NessaGatewayError.invalidAddress
    }
    guard url.scheme == "wss" || ["127.0.0.1", "[::1]", "::1"].contains(url.host ?? "") else {
      throw NessaGatewayError.invalidAddress
    }
    var uploadComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)!
    uploadComponents.scheme = url.scheme == "wss" ? "https" : "http"
    uploadComponents.path = "/attachments"
    uploadComponents.query = nil
    uploadComponents.fragment = nil
    uploadURL = uploadComponents.url
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
      } catch { await self?.transportFailed(task: task) }
    }
    let challengeData = try await waitForChallenge()
    let challenge = try JSONDecoder().decode(Challenge.self, from: challengeData)
    guard challenge.minVersion <= 1, challenge.maxVersion >= 1,
      challenge.expiresAt > Date().timeIntervalSince1970
    else { throw NessaGatewayError.incompatibleProtocol }
    let params = Authenticate(
      minVersion: 1, maxVersion: 1, nonce: challenge.nonce,
      credential: credential, client: .init(id: "nessa-ios"),
      surface: .init(kind: "panel", instance: instance))
    let result: Ready = try await request("session.authenticate", params: params)
    guard result.version == 1 else { throw NessaGatewayError.incompatibleProtocol }
    guard generation == connectionGeneration else { throw NessaGatewayError.disconnected }
    authenticated = true
  }

  public func list() async throws -> NessaConversationList {
    try requireConnection()
    return try await request("conversation.list", params: Empty())
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
    try requireConnection()
    let id = UUID().uuidString.lowercased()
    let _: Created = try await request(
      "conversation.create",
      params: Create(conversationId: id, requestId: UUID().uuidString, agent: agent, model: model))
    return id
  }
  public func delete(_ conversationID: String) async throws {
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
    try requireConnection()
    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty,
      text.utf8.count <= 8192
    else {
      throw NessaGatewayError.rejected("Messages must contain text and fit within 8 KiB.")
    }
    try attachmentPolicy.validate(attachments)
    let generation = connectionGeneration
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
    let executionID = UUID().uuidString.lowercased()
    let _: Ignored = try await request(
      "conversation.send",
      params: Send(
        conversationId: conversationID,
        requestId: UUID().uuidString, executionId: executionID, text: text,
        attachments: images, files: []))
    return executionID
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
    } catch NessaGatewayError.unknownSubscription {
      // A terminal publication can retire the remote subscription before cleanup arrives.
    } catch { if generation == connectionGeneration { close(error) } }
  }
  private func registrationSettled(_ token: String) {
    for waiter in registrationWaiters.removeValue(forKey: token) ?? [] {
      waiter.continuation.resume()
    }
  }
  public func disconnect() { close(NessaGatewayError.disconnected) }
  private func close(_ error: Error) {
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
    socket?.cancel(with: .goingAway, reason: nil)
    socket = nil
    subscriptions.finishAll(error)
    failPending(error)
    challenge = nil
  }
  private func requireConnection() throws {
    guard authenticated, socket != nil else { throw NessaGatewayError.disconnected }
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
    id: String = UUID().uuidString
  ) async throws -> R {
    guard let socket else { throw NessaGatewayError.disconnected }
    let data = try JSONEncoder().encode(
      Request(type: "req", id: id, method: method, params: params))
    let payload: Data = try await withCheckedThrowingContinuation { continuation in
      pending[id] = continuation
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
    return try JSONDecoder().decode(R.self, from: payload)
  }
  private func expire(_ id: String, error: Error) {
    timeouts.removeValue(forKey: id)?.cancel()
    let registration = subscriptions.awaiting(id)
    subscriptions.fail(id, error: error)
    registrationSettled(id)
    pending.removeValue(forKey: id)?.resume(throwing: error)
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
      guard let frame = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw NessaGatewayError.invalidFrame
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
        if frame["ok"] as? Bool == true {
          let registration = subscriptions.awaiting(id)
          do {
            let payload = try JSONSerialization.data(
              withJSONObject: frame["payload"] ?? [:], options: .fragmentsAllowed)
            if subscriptions.awaiting(id),
              let stopped = try subscriptions.activate(id, data: payload)
            {
              let generation = connectionGeneration
              _ = beginCleanup(stopped, generation: generation)
            }
            registrationSettled(id)
            waiter.resume(returning: payload)
          } catch {
            subscriptions.fail(id, error: error)
            registrationSettled(id)
            waiter.resume(throwing: error)
            if registration { close(error) }
          }
        } else {
          let error = frame["error"] as? [String: Any]
          subscriptions.fail(
            id,
            error: GatewayFailureDTO.failure(
              code: error?["code"] as? String, message: error?["message"] as? String))
          registrationSettled(id)
          waiter.resume(
            throwing: GatewayFailureDTO.failure(
              code: error?["code"] as? String, message: error?["message"] as? String))
        }
      } else if frame["type"] as? String == "event", let name = frame["event"] as? String,
        let payload = frame["payload"]
      {
        let bytes = try JSONSerialization.data(withJSONObject: payload)
        if let stopped = subscriptions.receive(name, payload: bytes) {
          let generation = connectionGeneration
          _ = beginCleanup(stopped, generation: generation)
        }
      }
    } catch { close(error) }
  }
  private func transportFailed(task: URLSessionWebSocketTask) {
    guard socket === task else { return }
    close(NessaGatewayError.disconnected)
  }
  private func failPending(_ error: Error) {
    for timeout in timeouts.values { timeout.cancel() }
    timeouts.removeAll()
    for waiter in pending.values { waiter.resume(throwing: error) }
    pending.removeAll()
    challengeWaiter?.resume(throwing: error)
    challengeWaiter = nil
  }
  private struct Empty: Encodable {}
  private struct Ignored: Decodable {}
  private struct Challenge: Decodable {
    let minVersion: Int
    let maxVersion: Int
    let nonce: String
    let expiresAt: Double
  }
  private struct Ready: Decodable { let version: Int }
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
