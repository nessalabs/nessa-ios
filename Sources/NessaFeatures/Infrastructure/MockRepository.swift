import Foundation

/// In-memory development adapter. It never opens a socket or stores credentials.
public actor MockRepository: MessagingRepository, AgentDirectory, ConversationFollowing {
  private var feeds:
    [UUID: (String?, AsyncThrowingStream<ConversationUpdate, Error>.Continuation)] = [:]
  private var revisions: [String: Int] = [:]
  private let incarnation = UUID().uuidString
  public func follow(_ id: String?, after: ConversationCursor?) throws
    -> AsyncThrowingStream<ConversationUpdate, Error>
  {
    try requireConnection()
    if let id { _ = try read(id) }
    let token = UUID()
    let (stream, continuation) = AsyncThrowingStream<ConversationUpdate, Error>.makeStream(
      bufferingPolicy: .bufferingNewest(1))
    continuation.onTermination = { [weak self] _ in Task { await self?.removeFeed(token) } }
    feeds[token] = (id, continuation)
    publish(to: token)
    return stream
  }
  private func removeFeed(_ token: UUID) { feeds.removeValue(forKey: token) }
  private func publish(to token: UUID) {
    guard let (id, continuation) = feeds[token] else { return }
    if let id {
      guard let view = threads[id] else {
        continuation.finish(
          throwing: ConversationFeedEnded(reason: .refused, code: "conversation_not_found"))
        feeds.removeValue(forKey: token)
        return
      }
      if let cursor = try? ConversationCursor(
        incarnation: incarnation, position: String(revisions[id] ?? 0))
      {
        continuation.yield(.view(cursor, view))
      }
    } else {
      continuation.yield(.list(NessaConversationList(conversations: summaries, complete: true)))
    }
  }
  private func changed(_ id: String) {
    revisions[id, default: 0] += 1
    for token in Array(feeds.keys) where feeds[token]?.0 == nil || feeds[token]?.0 == id {
      publish(to: token)
    }
  }
  private var connected = false
  private var generation = 0
  private var images: [String: Data] = [:]
  public func imageData(for attachment: NessaImageAttachment) throws -> Data? {
    try requireConnection()
    return images[attachment.digest]
  }
  private var summaries: [NessaConversation]
  private var threads: [String: NessaConversationView]
  private let profiles: [AgentProfile]
  public init(
    agents: [AgentProfile] = [
      AgentProfile(
        id: "nessa", displayName: "Nessa",
        prompt:
          "Development fixture: Help with everyday planning and ideas. Be thoughtful, clear, and ask before taking actions that need permission.",
        grantedAccess: ["This conversation (development fixture)"])
    ]
  ) {
    self.profiles = agents
    let titles = [
      "Nessa", "Weekend plans", "A little inspiration", "Things to remember", "Dinner ideas",
      "Tomorrow", "A fresh start", "Reading list", "Travel notes", "Daily check-in", "Focus time",
      "Ideas",
    ]
    let fixtureImage = MockAgentDetailsFixtures.image
    images[fixtureImage.digest] = MockAgentDetailsFixtures.imageData
    var summaries: [NessaConversation] = []
    var threads: [String: NessaConversationView] = [:]
    for (index, title) in titles.enumerated() {
      let id = String(format: "00000000-0000-4000-8000-%012d", index + 1)
      var messages = (0..<8).map { turn in
        NessaTurn(
          executionId: "\(id)-\(turn)",
          userText: turn == 0
            ? "Hi Nessa, can we talk about \(title.lowercased())?"
            : "What else should I keep in mind?", status: "completed", error: nil,
          parts: [
            NessaPart(
              offset: 0, kind: "text",
              text: turn == 0
                ? "Of course. I’m here with you. What would you like to start with?"
                : "Let’s take it one step at a time. We can make a little room for what matters today.",
              messageId: "reply-\(turn)")
          ])
      }
      messages[0].attachments = [fixtureImage]
      messages[0].files = [
        NessaFileAttachment(
          name: "Ideas.txt", mimeType: "text/plain",
          data: Data("A few ideas to explore together.\nDevelopment fixture.".utf8))
      ]
      threads[id] = NessaConversationView(
        conversationId: id, messages: messages, permissions: [], truncated: false,
        interactionViewError: nil, runtime: NessaRuntime(agent: "nessa"))
      summaries.append(
        NessaConversation(
          conversationId: id, title: title,
          preview: "Let’s make a little room for what matters today.",
          updatedAtMs: Date().timeIntervalSince1970 * 1000 - Double(index) * 3_600_000,
          running: false))
    }
    self.summaries = summaries
    self.threads = threads
  }
  public func connect(address: String, credential: String, instance: String) {
    generation += 1
    connected = true
  }
  public func disconnect() {
    let continuations = feeds.values.map { $0.1 }
    feeds.removeAll()
    for continuation in continuations {
      continuation.finish(throwing: NessaGatewayError.disconnected)
    }
    generation += 1
    connected = false
  }
  public func agents() throws -> [AgentProfile] {
    try requireConnection()
    return profiles
  }
  public func list() throws -> NessaConversationList {
    try requireConnection()
    return NessaConversationList(conversations: summaries, complete: true)
  }
  public func read(_ id: String) throws -> NessaConversationView {
    try requireConnection()
    guard let view = threads[id] else {
      throw NessaGatewayError.conversationNotFound
    }
    return view
  }
  public func create(agent: String?, model: String? = nil) throws -> String {
    try requireConnection()
    let id = UUID().uuidString.lowercased()
    threads[id] = NessaConversationView(
      conversationId: id, messages: [], permissions: [], truncated: false,
      interactionViewError: nil, runtime: NessaRuntime(agent: agent ?? "nessa", model: model))
    summaries.insert(
      NessaConversation(
        conversationId: id, title: "Nessa", preview: "New conversation",
        updatedAtMs: Date().timeIntervalSince1970 * 1000, running: false), at: 0)
    changed(id)
    return id
  }
  @discardableResult
  public func send(_ text: String, attachments: [DraftAttachment], conversationID: String) throws
    -> String
  {
    let current = try read(conversationID)
    var turn = NessaTurn(
      executionId: UUID().uuidString,
      userText: text + (attachments.filter { !$0.isImage }.map { "\n📎 " + $0.name }.joined()),
      status: "running", error: nil, parts: [])
    for attachment in attachments where attachment.isImage {
      images["mock:\(attachment.id)"] = attachment.data
    }
    turn.files = attachments.filter { !$0.isImage }.map {
      NessaFileAttachment(name: $0.name, mimeType: $0.mimeType, data: $0.data)
    }
    turn.attachments = attachments.filter(\.isImage).map {
      NessaImageAttachment(digest: "mock:\($0.id)", mimeType: $0.mimeType, size: $0.data.count)
    }
    threads[conversationID] = NessaConversationView(
      conversationId: conversationID, messages: current.messages + [turn],
      permissions: current.permissions, truncated: false, interactionViewError: nil,
      runtime: current.runtime)
    let title = summaries.first { $0.id == conversationID }?.title
    summaries.removeAll { $0.id == conversationID }
    summaries.insert(
      NessaConversation(
        conversationId: conversationID, title: title,
        preview: text.isEmpty ? "Photo" : text,
        updatedAtMs: Date().timeIntervalSince1970 * 1000, running: true), at: 0)
    changed(conversationID)
    let expectedGeneration = generation
    let executionID = turn.id
    Task {
      try? await Task.sleep(for: .seconds(1.2))
      guard !Task.isCancelled, generation == expectedGeneration, connected,
        let thread = threads[conversationID]
      else { return }
      let messages = thread.messages.map { message -> NessaTurn in
        guard message.id == executionID else { return message }
        var completed = NessaTurn(
          executionId: message.id, userText: message.userText,
          status: "completed", error: nil,
          parts: [
            NessaPart(
              offset: 0, kind: "text",
              text: "I’m here. Tell me a little more about that.", messageId: "reply:" + message.id)
          ])
        completed.attachments = message.attachments
        completed.files = message.files
        return completed
      }
      threads[conversationID] = NessaConversationView(
        conversationId: conversationID,
        messages: messages, permissions: thread.permissions, truncated: thread.truncated,
        interactionViewError: nil, runtime: thread.runtime)
      summaries = summaries.map { summary in
        guard summary.id == conversationID else { return summary }
        return NessaConversation(
          conversationId: summary.id, title: summary.title,
          preview: "I’m here. Tell me a little more about that.", updatedAtMs: summary.updatedAtMs,
          running: messages.contains { $0.status == "running" })
      }
      changed(conversationID)
    }
    return executionID
  }
  public func delete(_ conversationID: String) throws {
    _ = try read(conversationID)
    threads.removeValue(forKey: conversationID)
    summaries.removeAll { $0.id == conversationID }
    changed(conversationID)
  }
  public func answer(
    _ permission: NessaPermission, option: NessaPermission.Option, conversationID: String
  ) throws {
    _ = try read(conversationID)
    throw NessaGatewayError.rejected("No permission is pending in this mock conversation.")
  }
  private func requireConnection() throws { if !connected { throw NessaGatewayError.disconnected } }
}
