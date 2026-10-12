import Combine
import Foundation

@MainActor
public final class MessagesViewModel: ObservableObject {
  @Published public var conversations: [NessaConversation] = []
  @Published public private(set) var views: [String: NessaConversationView] = [:]
  @Published public private(set) var reactions: [String: String] = [:]
  private var reactionKey = ""
  @Published public private(set) var replyTargets: [String: String] = [:]
  private var replyKey = ""
  private var replyProjections: [String: (name: String, value: ConversationReplies)] = [:]
  private var listVersion = 0
  private var readVersions: [String: Int] = [:]
  private var deletedIDs: Set<String> = []
  @Published public private(set) var pendingDeletionIDs: Set<String> = []
  public var visibleConversations: [NessaConversation] {
    conversations.filter { !pendingDeletionIDs.contains($0.id) }
  }
  public func isDeleting(_ identifier: String) -> Bool {
    pendingDeletionIDs.contains(identifier)
      || agentThreads[identifier].map { pendingDeletionIDs.contains($0) } == true
  }
  @Published public var connected = false
  @Published public var busy = false
  @Published public var sending = false
  @Published public var error: String?
  @Published public var listComplete = true
  @Published public var agentProfiles: [AgentProfile] = []
  @Published public var pinnedChats: [String] = []
  @Published public var unreadChats: [String] = []
  @Published public var mutedChats: [String] = []
  @Published public private(set) var archivedChats: [String] = []
  @Published public var agentPreviews: [String: NessaConversationView] = [:]
  private var statusKey = ""
  private let preferences: any ChatPreferences
  private var conversationAgents: [String: String] = [:]
  private var identityKey = ""
  private var agentThreads: [String: String] = [:]
  private var pinKey = ""
  private var threadKey = ""
  private let service: MessagingService
  private let credentials: any NessaCredentialStoring
  private var generation = 0

  public init(
    service: MessagingService, credentials: any NessaCredentialStoring,
    preferences: any ChatPreferences
  ) {
    self.credentials = credentials
    self.service = service
    self.preferences = preferences
  }
  public func reaction(message: String, in conversation: String) -> String? {
    reactions[conversation + ":" + message]
  }
  public func react(_ emoji: String, message: String, in conversation: String) {
    let key = conversation + ":" + message
    if reactions[key] == emoji {
      reactions.removeValue(forKey: key)
    } else {
      reactions[key] = emoji
    }
    preferences.save(reactions, forKey: reactionKey)
  }
  public var attachmentPolicy: AttachmentPolicy { service.attachmentPolicy }
  public func replies(in conversation: String) -> [String: String] {
    let prefix = conversation + ":"
    return Dictionary(
      uniqueKeysWithValues: replyTargets.compactMap { key, value in
        key.hasPrefix(prefix) ? (String(key.dropFirst(prefix.count)), value) : nil
      })
  }
  public func replyProjection(in conversation: String) -> ConversationReplies {
    let name = agentName(for: conversation)
    if let cached = replyProjections[conversation], cached.name == name { return cached.value }
    let value = ConversationReplies(
      turns: views[conversation]?.messages ?? [],
      targets: replies(in: conversation), agentName: name)
    replyProjections[conversation] = (name, value)
    return value
  }
  public func imageData(for attachment: NessaImageAttachment) async -> Data? {
    try? await service.imageData(for: attachment)
  }
  public func isPinned(_ agent: String) -> Bool { pinnedChats.contains(agent) }
  public func canTogglePin(_ agent: String) -> Bool {
    isPinned(agent) || pinnedChats.count < NessaPinPolicy.maximumAgents
  }
  public func togglePin(_ agent: String) {
    guard canTogglePin(agent) else { return }
    if isPinned(agent) { pinnedChats.removeAll { $0 == agent } } else { pinnedChats.append(agent) }
    preferences.save(pinnedChats, forKey: pinKey)
  }
  public func markUnread(_ agent: String) {
    if !unreadChats.contains(agent) { unreadChats.append(agent) }
    saveStatus()
  }
  public func toggleAlerts(_ agent: String) {
    if mutedChats.contains(agent) {
      mutedChats.removeAll { $0 == agent }
    } else {
      mutedChats.append(agent)
    }
    saveStatus()
  }
  private func saveStatus() {
    preferences.save(unreadChats, forKey: statusKey + ".unread")
    preferences.save(mutedChats, forKey: statusKey + ".muted")
  }
  public func setArchived(_ archived: Bool, conversationID: String) {
    guard conversations.contains(where: { $0.id == conversationID }) else { return }
    archivedChats.removeAll { $0 == conversationID }
    if archived {
      archivedChats.append(conversationID)
      if isPinned(conversationID) { togglePin(conversationID) }
    }
    preferences.save(archivedChats, forKey: statusKey + ".archived")
  }
  public func deleteConversations(_ ids: Set<String>) async {
    let expectedGeneration = generation
    let targets = ids.filter { id in conversations.contains(where: { $0.id == id }) }
    pendingDeletionIDs.formUnion(targets)
    defer {
      if generation == expectedGeneration { pendingDeletionIDs.subtract(targets) }
    }
    for id in targets.sorted() {
      guard generation == expectedGeneration, !Task.isCancelled else { return }
      await deleteConversation(for: id)
    }
  }
  public func loadPreview(_ agent: String) async {
    guard let id = conversationID(for: agent), connected, !isDeleting(agent) else { return }
    let currentGeneration = generation
    let version = readVersions[id] ?? 0
    do {
      let result = try await service.read(id)
      guard currentGeneration == generation, !deletedIDs.contains(id),
        !pendingDeletionIDs.contains(id),
        (readVersions[id] ?? 0) == version
      else { return }
      agentPreviews[agent] = result
    } catch { /* A preview must not interrupt inbox navigation. */  }
  }
  private func conversationID(for identifier: String) -> String? {
    conversations.contains { $0.id == identifier } ? identifier : agentThreads[identifier]
  }
  public func chatName(_ id: String) -> String {
    conversations.first { $0.id == id }?.title ?? agentName(for: id)
  }
  public func hasConversation(_ agent: String) -> Bool { conversationID(for: agent) != nil }
  public func deleteConversation(for agent: String) async {
    guard let id = conversationID(for: agent) else { return }
    let currentGeneration = generation
    pendingDeletionIDs.insert(id)
    listVersion += 1
    readVersions[id, default: 0] += 1
    defer {
      if generation == currentGeneration { pendingDeletionIDs.remove(id) }
    }
    do {
      try await service.delete(id)
      guard generation == currentGeneration else { return }
      removeDeletedConversation(id, identifier: agent)
    } catch {
      if generation == currentGeneration {
        self.error = error.localizedDescription
        // A failed acknowledgement can follow a committed gateway tombstone.
        try? await refreshList()
        if generation == currentGeneration, listComplete,
          !conversations.contains(where: { $0.id == id })
        {
          removeDeletedConversation(id, identifier: agent)
        }
      }
    }
  }
  private func removeDeletedConversation(_ id: String, identifier agent: String) {
    deletedIDs.insert(id)
    listVersion += 1
    readVersions[id, default: 0] += 1
    conversationAgents.removeValue(forKey: id)
    preferences.save(conversationAgents, forKey: identityKey)
    agentThreads = agentThreads.filter { $0.value != id }
    preferences.save(agentThreads, forKey: threadKey)
    agentPreviews.removeValue(forKey: agent)
    unreadChats.removeAll { $0 == agent }
    archivedChats.removeAll { $0 == id }
    preferences.save(archivedChats, forKey: statusKey + ".archived")
    saveStatus()
    if isPinned(agent) { togglePin(agent) }
    conversations.removeAll { $0.id == id }
    views.removeValue(forKey: id)
    reactions = reactions.filter { !$0.key.hasPrefix(id + ":") }
    preferences.save(reactions, forKey: reactionKey)
    replyTargets = replyTargets.filter { !$0.key.hasPrefix(id + ":") }
    preferences.save(replyTargets, forKey: replyKey)
    replyProjections.removeValue(forKey: id)
  }
  public func openAgent(_ agent: String) async -> String? {
    if let id = agentThreads[agent] {
      let currentGeneration = generation
      await refresh(id)
      guard generation == currentGeneration, views[id] != nil else { return nil }
      if unreadChats.contains(agent) {
        unreadChats.removeAll { $0 == agent }
        saveStatus()
      }
      return id
    }
    return await create(agent: agent)
  }
  public func agentID(for conversationID: String) -> String? {
    agentThreads.first { $0.value == conversationID }?.key
  }
  public func agentName(for conversationID: String) -> String {
    let agentID = conversationAgents[conversationID] ?? agentID(for: conversationID)
    return agentProfiles.first { $0.id == agentID }?.displayName ?? agentID?.capitalized
      ?? agentProfiles.first?.displayName ?? "Agent"
  }
  public func savedCredential() -> String { credentials.load() ?? "" }
  public func connect(address: String, credential: String, instance: String) async {
    guard !busy else { return }
    busy = true
    connected = false
    error = nil
    generation += 1
    sending = false
    conversations = []
    agentProfiles = []
    pinnedChats = []
    unreadChats = []
    mutedChats = []
    archivedChats = []
    reactions = [:]
    replyTargets = [:]
    replyProjections = [:]
    agentPreviews = [:]
    conversationAgents = [:]
    agentThreads = [:]
    deletedIDs = []
    pendingDeletionIDs = []
    views = [:]
    readVersions = [:]
    do {
      try await service.connect(address: address, credential: credential, instance: instance)
      let scope = address + ":" + instance
      pinKey = "nessa.pinnedChats." + scope
      threadKey = "nessa.agentThreads." + scope
      identityKey = "nessa.conversationAgents." + scope
      conversationAgents = preferences.mapping(forKey: identityKey) ?? [:]
      agentProfiles = try await service.agents()
      reactionKey = "nessa.reactions." + scope
      reactions = preferences.mapping(forKey: reactionKey) ?? [:]
      replyKey = "nessa.replies." + scope
      replyTargets = preferences.mapping(forKey: replyKey) ?? [:]
      statusKey = "nessa.status." + scope
      unreadChats = preferences.strings(forKey: statusKey + ".unread") ?? []
      mutedChats = preferences.strings(forKey: statusKey + ".muted") ?? []
      archivedChats = preferences.strings(forKey: statusKey + ".archived") ?? []
      agentPreviews = [:]
      let savedPins = preferences.strings(forKey: pinKey) ?? []
      pinnedChats = NessaPinPolicy.normalize(savedPins)
      preferences.save(pinnedChats, forKey: pinKey)
      agentThreads = preferences.mapping(forKey: threadKey) ?? [:]
      try await refreshList()
      try credentials.save(credential)
      connected = true
    } catch {
      conversations = []
      agentProfiles = []
      pinnedChats = []
      unreadChats = []
      mutedChats = []
      archivedChats = []
      reactions = [:]
      replyTargets = [:]
      agentThreads = [:]
      conversationAgents = [:]
      await service.disconnect()
      connected = false
      self.error = error.localizedDescription
    }
    busy = false
  }
  public func refreshList() async throws {
    let currentGeneration = generation
    listVersion += 1
    let version = listVersion
    do {
      let result = try await service.list()
      guard currentGeneration == generation, !Task.isCancelled, version == listVersion else {
        return
      }
      let visible = result.conversations.filter { !deletedIDs.contains($0.id) }
      if conversations != visible { conversations = visible }
      if listComplete != result.complete { listComplete = result.complete }
    } catch {
      guard currentGeneration == generation, !Task.isCancelled, version == listVersion else {
        return
      }
      throw error
    }
  }
  public func refresh(_ id: String) async {
    guard !deletedIDs.contains(id), !pendingDeletionIDs.contains(id) else { return }
    let currentGeneration = generation
    let version = (readVersions[id] ?? 0) + 1
    readVersions[id] = version
    do {
      let result = try await service.read(id)
      guard currentGeneration == generation, !Task.isCancelled, !pendingDeletionIDs.contains(id),
        readVersions[id] == version
      else {
        return
      }
      if views[id] != result {
        replyProjections.removeValue(forKey: id)
        views[id] = result
      }
      let updatedUnread = unreadChats.filter { $0 != id && $0 != result.runtime?.agent }
      if updatedUnread != unreadChats {
        unreadChats = updatedUnread
        saveStatus()
      }
      if let agent = result.runtime?.agent {
        if conversationAgents[id] != agent {
          conversationAgents[id] = agent
          preferences.save(conversationAgents, forKey: identityKey)
        }
        if agentThreads[agent] != id {
          agentThreads[agent] = id
          preferences.save(agentThreads, forKey: threadKey)
        }
      }
    } catch {
      guard currentGeneration == generation, !Task.isCancelled, readVersions[id] == version else {
        return
      }
      if case NessaGatewayError.disconnected = error { connected = false }
      self.error = error.localizedDescription
    }
  }
  public func create(agent: String? = nil) async -> String? {
    guard connected, !busy else { return nil }
    let currentGeneration = generation
    busy = true
    defer { if generation == currentGeneration { busy = false } }
    do {
      let profile = agentProfiles.first { $0.id == agent }
        ?? (agent == nil && agentProfiles.count == 1 ? agentProfiles.first : nil)
      let id = try await service.create(agent: agent, model: profile?.phoneModel)
      guard generation == currentGeneration, !Task.isCancelled else { return nil }
      listVersion += 1
      replyProjections.removeValue(forKey: id)
      views[id] = NessaConversationView(
        conversationId: id, messages: [], permissions: [],
        truncated: false, interactionViewError: nil,
        runtime: agent.map { NessaRuntime(agent: $0) })
      conversations.insert(
        NessaConversation(
          conversationId: id, title: nil, preview: nil,
          updatedAtMs: Date().timeIntervalSince1970 * 1000, running: false), at: 0)
      if let agent {
        agentThreads[agent] = id
        unreadChats.removeAll { $0 == agent }
        saveStatus()
        preferences.save(agentThreads, forKey: threadKey)
      }
      Task { [weak self] in
        guard let self, self.generation == currentGeneration else { return }
        do { try await self.refreshList() } catch {
          if self.generation == currentGeneration { self.error = error.localizedDescription }
        }
      }
      return id
    } catch {
      if generation == currentGeneration { self.error = error.localizedDescription }
      return nil
    }
  }
  public func send(
    _ text: String, attachments: [DraftAttachment] = [], reply: MessageReply? = nil,
    to id: String
  ) async -> Bool {
    guard !sending else { return false }
    let currentGeneration = generation
    sending = true
    defer { if generation == currentGeneration { sending = false } }
    do {
      let executionID = try await service.send(
        text, attachments: attachments, reply: reply, conversationID: id)
      guard generation == currentGeneration else { return true }
      if let reply, !deletedIDs.contains(id), !pendingDeletionIDs.contains(id) {
        replyProjections.removeValue(forKey: id)
        replyTargets[id + ":" + executionID] = reply.id
        preferences.save(replyTargets, forKey: replyKey)
      }
      await refresh(id)
      guard generation == currentGeneration else { return true }
      do { try await refreshList() } catch {
        if generation == currentGeneration { self.error = error.localizedDescription }
      }
      return true
    } catch {
      if generation == currentGeneration { self.error = error.localizedDescription }
      return false
    }
  }
  public func answer(_ permission: NessaPermission, option: NessaPermission.Option, in id: String)
    async
  {
    let currentGeneration = generation
    do {
      try await service.answer(permission, option: option, conversationID: id)
      guard generation == currentGeneration else { return }
      await refresh(id)
    } catch { if generation == currentGeneration { self.error = error.localizedDescription } }
  }
}
