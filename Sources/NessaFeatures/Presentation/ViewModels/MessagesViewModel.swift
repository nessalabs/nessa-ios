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
  private var viewCursors: [String: ConversationCursor] = [:]
  private var unlistedCreations: [String: NessaConversation] = [:]
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
  @Published public private(set) var connectionRevision = 0
  @Published public private(set) var reconnecting = false
  @Published public private(set) var deliveryScopeRevision = 0
  @Published public private(set) var pendingCommands: [PreparedConversationCommand] = []
  @Published public private(set) var pendingLoadError: String?
  @Published public private(set) var acknowledgedCommands: Set<String> = []
  private var acknowledgmentOrder: [String] = []
  @Published public private(set) var checkingCommands: Set<String> = []
  private var commandActions: [String: UUID] = [:]
  private var pendingVersion = 0
  public var pendingCreations: [PreparedConversationCommand] {
    pendingCommands.filter { if case .create = $0 { true } else { false } }
  }
  public func pendingSubmissions(in id: String) -> [PreparedConversationCommand] {
    pendingCommands.filter { if case .submit = $0 { $0.conversationID == id } else { false } }
  }
  public func canSubmit(in id: String) -> Bool {
    connected && pendingLoadError == nil && pendingSubmissions(in: id).isEmpty
  }
  private let snapshots: PhoneSnapshotSession?
  private var snapshotLease: PhoneSnapshotSession.Lease?
  private let recovery: ConnectionRecovery?
  private var recoveryTask: Task<Void, Never>?
  private var retirementTask: Task<Void, Never>?
  private var manualAttempt: Int?
  private var foreground = true
  private struct Profile: Equatable, Sendable {
    let address: String
    let credential: String
    let instance: String
  }
  private var profile: Profile?

  public init(
    service: MessagingService, credentials: any NessaCredentialStoring,
    preferences: any ChatPreferences, snapshots: PhoneSnapshotSession? = nil,
    recovery: ConnectionRecovery? = nil
  ) {
    self.credentials = credentials
    self.service = service
    self.preferences = preferences
    self.snapshots = snapshots
    self.recovery = recovery
  }
  deinit { recoveryTask?.cancel() }
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
    guard connected, let id = conversationID(for: agent) else { return }
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
      await removeDeletedConversation(id, identifier: agent)
    } catch {
      if generation == currentGeneration {
        self.error = error.localizedDescription
        // The inbox excludes archived chats, so its absence cannot prove deletion.
        try? await refreshList()
        guard generation == currentGeneration else { return }
        do { _ = try await service.read(id) } catch NessaGatewayError.conversationNotFound {
          if generation == currentGeneration {
            await removeDeletedConversation(id, identifier: agent)
          }
        } catch {
          // An uncertain read preserves the cached chat and preferences.
        }
      }
    }
  }
  private func removeDeletedConversation(_ id: String, identifier agent: String) async {
    deletedIDs.insert(id)
    unlistedCreations.removeValue(forKey: id)
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
    if let snapshotLease { await snapshots?.remove(id, lease: snapshotLease) }
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
    recoveryTask?.cancel()
    recoveryTask = nil
    reconnecting = false
    let next = Profile(address: address, credential: credential, instance: instance)
    if profile != next {
      deliveryScopeRevision += 1
      acknowledgedCommands = []
      acknowledgmentOrder = []
    }
    profile = next
    generation += 1
    connectionRevision += 1
    let expected = generation
    manualAttempt = expected
    defer {
      if manualAttempt == expected {
        manualAttempt = nil
        busy = false
      }
    }
    busy = true
    connected = false
    sending = false
    pendingCommands = []
    pendingLoadError = nil
    commandActions = [:]
    checkingCommands = []
    error = nil
    snapshotLease = nil
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
    viewCursors = [:]
    unlistedCreations = [:]
    loadPreferences(next)
    do {
      try await hydrate(next, generation: expected)
      guard generation == expected, foreground else { return }
      try await dial(next, generation: expected)
    } catch {
      guard generation == expected else { return }
      if error is CancellationError {
        busy = false
        return
      }
      if ConnectionRecovery.retryable(error), recovery != nil {
        manualAttempt = nil
        busy = false
        startRecovery()
      } else {
        if !ConnectionRecovery.retryable(error) {
          conversations = []
          views = [:]
          pinnedChats = []
          agentProfiles = []
        }
        self.error = error.localizedDescription
      }
    }
    if generation == expected { busy = false }
  }
  private func hydrate(_ profile: Profile, generation expected: Int) async throws {
    guard let snapshots else { return }
    let (lease, saved) = try await snapshots.prepare(
      PhoneCacheScope(
        address: profile.address, credential: profile.credential, instance: profile.instance))
    guard generation == expected, !Task.isCancelled else { throw CancellationError() }
    snapshotLease = lease
    if let saved {
      conversations = saved.list?.conversations ?? []
      listComplete = saved.list?.complete ?? true
      views = saved.views
      agentProfiles = saved.agents
    }
  }
  private func loadPreferences(_ profile: Profile) {
    let scope = profile.address + ":" + profile.instance
    pinKey = "nessa.pinnedChats." + scope
    threadKey = "nessa.agentThreads." + scope
    identityKey = "nessa.conversationAgents." + scope
    conversationAgents = preferences.mapping(forKey: identityKey) ?? [:]
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
  }
  private func dial(_ profile: Profile, generation expected: Int) async throws {
    await retirementTask?.value
    guard generation == expected, foreground, !Task.isCancelled else { throw CancellationError() }
    if snapshotLease == nil { try await hydrate(profile, generation: expected) }
    guard generation == expected, foreground, !Task.isCancelled else { throw CancellationError() }
    var receipt: GatewayConnectionLease?
    do {
      receipt = try await service.connect(
        address: profile.address, credential: profile.credential, instance: profile.instance)
      guard generation == expected, foreground, !Task.isCancelled else { throw CancellationError() }
      let agents = try await service.agents()
      guard generation == expected, !Task.isCancelled else { throw CancellationError() }
      agentProfiles = agents
      try await refreshList()
      guard generation == expected, foreground, !Task.isCancelled else { throw CancellationError() }
      do {
        let pending = try await service.pendingCommands()
        guard generation == expected, foreground, !Task.isCancelled else {
          throw CancellationError()
        }
        pendingCommands = pending
        pendingLoadError = nil
      } catch {
        guard generation == expected, foreground, !Task.isCancelled else {
          throw CancellationError()
        }
        pendingLoadError = error.localizedDescription
      }
      let lease = snapshotLease
      if let lease { await snapshots?.recordAgents(agents, lease: lease) }
      guard generation == expected, foreground, !Task.isCancelled else { throw CancellationError() }
      try credentials.save(profile.credential)
      connected = true
      connectionRevision += 1
    } catch {
      await service.retire(receipt)
      throw error
    }
  }
  /// Retire authority before waiting for any cache I/O. The cache writer is already owned.
  public func suspendConnection() async {
    foreground = false
    generation += 1
    connectionRevision += 1
    recoveryTask?.cancel()
    recoveryTask = nil
    manualAttempt = nil
    reconnecting = false
    connected = false
    busy = false
    sending = false
    commandActions = [:]
    checkingCommands = []
    unlistedCreations = [:]
    let service = service
    let retirement = Task { await service.disconnect() }
    retirementTask = retirement
    await retirement.value
    let snapshots = snapshots
    Task { await snapshots?.flush() }
  }
  public func resumeConnection() {
    foreground = true
    if !connected { startRecovery() }
  }
  private func startRecovery() {
    guard let recovery, let profile, foreground, recoveryTask == nil, manualAttempt == nil
    else { return }
    let expected = generation
    reconnecting = true
    recoveryTask = Task { [weak self] in
      defer {
        if let self, self.generation == expected {
          self.recoveryTask = nil
          self.reconnecting = false
        }
      }
      do {
        try await recovery.run { [weak self] in
          guard let self else { throw CancellationError() }
          try await self.dial(profile, generation: expected)
        }
      } catch {
        guard let self, self.generation == expected, !(error is CancellationError) else { return }
        self.error = error.localizedDescription
      }
    }
  }
  private func connectionLost(_ error: Error, generation expected: Int) {
    guard generation == expected else { return }
    if ConnectionRecovery.retryable(error) {
      if connected {
        connected = false
        busy = false
        sending = false
        commandActions = [:]
        checkingCommands = []
        if manualAttempt == expected { manualAttempt = nil }
        unlistedCreations = [:]
        generation += 1
        connectionRevision += 1
      }
      if recovery != nil {
        startRecovery()
        return
      }
    }
    self.error = error.localizedDescription
  }
  private func cache(_ update: ConversationUpdate) async {
    if let snapshotLease { await snapshots?.record(update, lease: snapshotLease) }
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
      await cache(.list(applyList(result)))
    } catch {
      guard currentGeneration == generation, !Task.isCancelled, version == listVersion else {
        return
      }
      throw error
    }
  }
  private func applyList(_ result: NessaConversationList) -> NessaConversationList {
    let observed = Set(result.conversations.map(\.id))
    unlistedCreations = unlistedCreations.filter { !observed.contains($0.key) }
    var visible = result.conversations.filter { !deletedIDs.contains($0.id) }
    visible += unlistedCreations.values
    if !unlistedCreations.isEmpty { visible.sort { $0.updatedAtMs > $1.updatedAtMs } }
    if conversations != visible { conversations = visible }
    if listComplete != result.complete { listComplete = result.complete }
    return NessaConversationList(conversations: visible, complete: result.complete)
  }
  public func refresh(_ id: String) async {
    guard connected, !deletedIDs.contains(id), !pendingDeletionIDs.contains(id) else { return }
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
      apply(result, to: id)
      let cursor = try ConversationCursor(incarnation: "snapshot", position: "0")
      await cache(.view(cursor, result))
    } catch {
      guard currentGeneration == generation, !Task.isCancelled, readVersions[id] == version else {
        return
      }
      connectionLost(error, generation: currentGeneration)
    }
  }
  private func apply(_ result: NessaConversationView, to id: String) {
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
  }
  public func watchInbox() async { await watch(nil) }
  public func watchConversation(_ id: String) async { await watch(id) }
  private func watch(_ id: String?) async {
    let expectedGeneration = generation
    guard connected else { return }
    do {
      try await service.watch(id, after: id.flatMap { viewCursors[$0] }) { [weak self] update in
        try await self?.receive(update, in: id, generation: expectedGeneration)
      }
    } catch is CancellationError {
      return
    } catch {
      guard generation == expectedGeneration, !Task.isCancelled else { return }
      connectionLost(error, generation: expectedGeneration)
    }
  }
  private func receive(_ update: ConversationUpdate, in id: String?, generation expected: Int)
    async throws
  {
    guard generation == expected, !Task.isCancelled else { throw CancellationError() }
    var accepted = update
    switch update {
    case .list(let list):
      listVersion += 1
      accepted = .list(applyList(list))
    case .view(let cursor, let view):
      guard !deletedIDs.contains(view.conversationId),
        !pendingDeletionIDs.contains(view.conversationId)
      else { return }
      viewCursors[view.conversationId] = cursor
      readVersions[view.conversationId, default: 0] += 1
      apply(view, to: view.conversationId)
    }
    await cache(accepted)
  }
  public func create(agent: String? = nil) async -> String? {
    guard connected, !busy, pendingLoadError == nil, pendingCreations.isEmpty else { return nil }
    let currentGeneration = generation
    let originalProfile = profile
    busy = true
    defer { if generation == currentGeneration { busy = false } }
    do {
      let profile =
        agentProfiles.first { $0.id == agent }
        ?? (agent == nil && agentProfiles.count == 1 ? agentProfiles.first : nil)
      let intent = PreparedConversationCommand.Creation(
        requestID: UUID().uuidString.lowercased(),
        conversationID: UUID().uuidString.lowercased(), agent: agent, model: profile?.phoneModel)
      let id: String
      do { id = try await service.create(intent) } catch {
        if let failure = error as? CommandDeliveryFailure, let accepted = failure.acknowledgment,
          self.profile == originalProfile, failure.command == .create(intent),
          accepted.validates(failure.command)
        {
          recordAcknowledgment(failure.command.requestID)
        }
        throw error
      }
      guard generation == currentGeneration, !Task.isCancelled else { return nil }
      listVersion += 1
      replyProjections.removeValue(forKey: id)
      views[id] = NessaConversationView(
        conversationId: id, messages: [], permissions: [],
        truncated: false, interactionViewError: nil,
        runtime: agent.map { NessaRuntime(agent: $0) })
      if !conversations.contains(where: { $0.id == id }) {
        let row = NessaConversation(
          conversationId: id, title: nil, preview: nil,
          updatedAtMs: Date().timeIntervalSince1970 * 1000, running: false)
        unlistedCreations[id] = row
        conversations.insert(row, at: 0)
      }
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
      if generation == currentGeneration { await refreshPendingCommands() }
      return nil
    }
  }
  public func send(
    _ text: String, attachments: [DraftAttachment] = [], reply: MessageReply? = nil,
    to id: String, identity: MessageCommandIdentity = MessageCommandIdentity()
  ) async -> Bool {
    guard canSubmit(in: id), !sending else { return false }
    let currentGeneration = generation
    let currentProfile = profile
    sending = true
    defer { if generation == currentGeneration { sending = false } }
    do {
      let executionID = try await service.send(
        text, attachments: attachments, reply: reply, conversationID: id, identity: identity)
      if profile == currentProfile { recordAcknowledgment(identity.requestID) }
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
      let known = (error as? CommandDeliveryFailure).flatMap {
        failure -> PreparedConversationCommand? in
        guard case .submit(let value) = failure.command,
          value.requestID == identity.requestID, value.executionID == identity.executionID,
          value.conversationID == id, failure.acknowledgment?.validates(failure.command) == true
        else { return nil }
        return failure.command
      }
      if let known, profile == currentProfile { recordAcknowledgment(known.requestID) }
      if let known, profile == currentProfile { rememberReply(known) }
      if generation == currentGeneration { self.error = error.localizedDescription }
      if profile == currentProfile { await refreshPendingCommands() }
      return known != nil
    }
  }
  public func refreshPendingCommands() async {
    guard connected else { return }
    let expected = generation
    pendingVersion += 1
    let version = pendingVersion
    do {
      let pending = try await service.pendingCommands()
      guard generation == expected, pendingVersion == version, !Task.isCancelled else { return }
      pendingCommands = pending
      pendingLoadError = nil
    } catch {
      guard generation == expected, pendingVersion == version, !Task.isCancelled else { return }
      pendingLoadError = error.localizedDescription
    }
  }
  public func reconnectDeliveryState() async {
    guard let profile else { return }
    await connect(
      address: profile.address, credential: profile.credential, instance: profile.instance)
  }
  /// Receipt checks never dispatch. Retry is explicitly requested for the frozen intent.
  public func recoverCommand(_ requestID: String, retry: Bool) async -> String? {
    guard connected, pendingLoadError == nil, !checkingCommands.contains(requestID) else {
      return nil
    }
    guard let originalCommand = pendingCommands.first(where: { $0.requestID == requestID }) else {
      return nil
    }
    let expected = generation
    let originalProfile = profile
    let token = UUID()
    commandActions[requestID] = token
    checkingCommands.insert(requestID)
    defer {
      if commandActions[requestID] == token {
        commandActions.removeValue(forKey: requestID)
        checkingCommands.remove(requestID)
      }
    }
    do {
      let result: ResolvedConversationCommand?
      if retry {
        result = try await service.retryCommand(requestID)
      } else {
        result = try await service.checkCommand(requestID)
      }
      guard let result else { return nil }
      guard result.command == originalCommand, result.acknowledgment.validates(result.command)
      else { throw NessaGatewayError.invalidFrame }
      if profile == originalProfile { recordAcknowledgment(requestID) }
      guard generation == expected, !Task.isCancelled else { return nil }
      if case .submit(let value) = result.command {
        rememberReply(result.command)
        await refresh(value.conversationID)
      }
      try await refreshList()
      await refreshPendingCommands()
      guard generation == expected, !Task.isCancelled else { return nil }
      if case .create(let value) = result.command { return value.conversationID }
    } catch {
      if let failure = error as? CommandDeliveryFailure, let accepted = failure.acknowledgment,
        profile == originalProfile, failure.command == originalCommand,
        accepted.validates(failure.command)
      {
        recordAcknowledgment(requestID)
        rememberReply(failure.command)
      }
      if generation == expected { self.error = error.localizedDescription }
      if profile == originalProfile { await refreshPendingCommands() }
    }
    return nil
  }
  private func recordAcknowledgment(_ requestID: String) {
    guard acknowledgedCommands.insert(requestID).inserted else { return }
    acknowledgmentOrder.append(requestID)
    while acknowledgmentOrder.count > 256 {
      acknowledgedCommands.remove(acknowledgmentOrder.removeFirst())
    }
  }
  private func rememberReply(_ command: PreparedConversationCommand) {
    guard case .submit(let value) = command, let parent = value.replyTo else { return }
    replyTargets[value.conversationID + ":" + value.executionID] = parent
    preferences.save(replyTargets, forKey: replyKey)
    replyProjections.removeValue(forKey: value.conversationID)
  }
  public func answer(_ permission: NessaPermission, option: NessaPermission.Option, in id: String)
    async
  {
    guard connected else { return }
    let currentGeneration = generation
    do {
      try await service.answer(permission, option: option, conversationID: id)
      guard generation == currentGeneration else { return }
      await refresh(id)
    } catch { if generation == currentGeneration { self.error = error.localizedDescription } }
  }
}
