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
  private struct ReplyProjection {
    let name: String
    let turns: [NessaTurn]
    let targets: [String: String]
    let value: ConversationReplies
  }
  private var replyProjections: [String: ReplyProjection] = [:]
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
  /// The chats the gateway holds archived, read when the Archived list is shown. The
  /// gateway decides which chats are archived; a new message there unarchives one, and the
  /// inbox feed (which lists only unarchived chats) showing it again takes it off this list.
  /// Their rows also stay in `conversations`, so opening and previewing work the same.
  @Published public private(set) var archivedConversations: [NessaConversation] = []
  public var archivedChats: [String] { archivedConversations.map(\.id) }
  public enum PreviewState: Equatable {
    case available(NessaConversationView)
    case loading, empty, unavailable
  }
  @Published private var previewViews: [String: NessaConversationView] = [:]
  private struct PreviewRead: Sendable {
    let token: UUID
    let task: Task<Void, Never>
  }
  private var previewReads: [String: PreviewRead] = [:]
  @Published private var loadingPreviews: Set<String> = []
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
    connected && conversationAuthorityReady && !accessRevoked
      && (phoneChat != nil || !unavailableNativeIDs.contains(id))
      && pendingLoadError == nil && pendingSubmissions(in: id).isEmpty
  }
  public func phoneDeliveries(in id: String) -> [PhoneOutboxView] {
    phoneDeliveries.filter {
      $0.conversationID == id && !($0.outcome == .draft || $0.outcome.claimsSubmission)
    }
  }
  public func submissionUnavailableReason(in id: String) -> String? {
    if accessRevoked { return "This phone’s access was revoked." }
    if !connected { return "Connect to send messages." }
    if phoneSetupBusy { return "Updating connection…" }
    if phoneChat == nil && unavailableNativeIDs.contains(id) {
      return "This chat isn’t available on this phone."
    }
    if phoneChat == nil && nativeConfigured && !nativeCommandReady {
      return phoneSyncError ?? "Chat connection is unavailable."
    }
    return nil
  }
  private let snapshots: PhoneSnapshotSession?
  private var snapshotLease: PhoneSnapshotSession.Lease?
  private let recovery: ConnectionRecovery?
  private var recoveryTask: Task<Void, Never>?
  private var retirementTask: Task<Void, Never>?
  private var manualAttempt: Int?
  private var foreground = true
  @Published public private(set) var automaticConnectionEnabled = true
  private var originalConnection: Profile?
  private var deletionDrains: [UUID: Task<Void, Never>] = [:]
  private static let automaticConnectionKey = "nessa.connection.automatic"
  private static let savedConnectionKey = "nessa.connection.saved"
  private struct Profile: Equatable, Sendable {
    let address: String
    let credential: String
    let instance: String
    /// The paired Mac this profile reaches over its native link, with no
    /// credential of its own; `nil` for a gateway address.
    var linked: UUID? = nil
    static func == (lhs: Self, rhs: Self) -> Bool {
      lhs.address.utf8.elementsEqual(rhs.address.utf8)
        && lhs.credential.utf8.elementsEqual(rhs.credential.utf8)
        && lhs.instance.utf8.elementsEqual(rhs.instance.utf8)
        && lhs.linked == rhs.linked
    }
  }
  private var profile: Profile?
  /// The paired Mac the product session goes to, and how to open it; set by
  /// `connectLinked` and read again by every reconnect.
  private var linkedDesktop: LinkedDesktop?
  private var linkedProducts: (any LinkedProductOpening)?
  /// The paired Mac this connection reaches, if it is a linked one.
  public var linkedDesktopID: UUID? { profile?.linked }
  private let phoneSync: (any PhoneSyncRunning)?
  private let phoneChat: PhoneProductChat?
  private let conversationSharing: PhoneConversationSharing?
  @Published public private(set) var phoneOwnerChoices: NessaConversationList?
  @Published public private(set) var pendingPhoneShares: [PhoneConversationShareIntent] = []
  @Published public private(set) var phoneSharingMessage: String?
  @Published public private(set) var phoneSharingLoadError: String?
  public private(set) var phoneSharingFailure: (any Error)?
  public var phoneSharingAvailable: Bool { conversationSharing != nil && nativeReceiverBound }
  public func needsPhoneSharing(in id: String) -> Bool {
    phoneSharingAvailable && (unavailableNativeIDs.contains(id) || views[id] == nil)
  }
  @Published public private(set) var phoneProfile: PhoneProfileSnapshot?
  @Published public private(set) var phoneSyncError: String?
  public private(set) var phoneSyncFailure: (any Error)?
  @Published public private(set) var nativeHistoryReady = false
  @Published public private(set) var nativeCommandReady = false
  public private(set) var acceptedLease: GatewayConnectionLease?
  private var nativeConfigured = false
  private var nativeOfflineEligible = false
  private var nativeNeedsRestore = true
  private var nativeReadTask: Task<Void, Never>?
  private var nativeReadToken: UUID?
  private var nativeReadTargets: Set<String> = []
  private var nativeReadRequested = false
  private var unavailableNativeIDs: Set<String> = []
  private var phoneStartupTask: Task<PhoneSyncStartup?, Error>?
  private var phoneStartupToken: UUID?
  @Published public private(set) var phoneSetupBusy = false
  @Published public private(set) var phoneInvitations: [GatewayPairingStatus] = []
  private var phoneSetupTask: Task<Bool, Never>?
  private var phoneSetupToken: UUID?
  public var phoneSyncAvailable: Bool { phoneSync != nil }
  public var currentGatewayAddress: String? { profile?.address }
  public var currentSurfaceInstance: String? { profile?.instance }
  public var canLoadLegacyCredential: Bool {
    !nativeConfigured && !busy && (phoneSync == nil || !nativeNeedsRestore)
  }
  @Published public private(set) var phoneDeliveries: [PhoneOutboxView] = []
  @Published public private(set) var accessRevoked = false
  public var conversationAuthorityReady: Bool {
    if phoneChat != nil { return !phoneSetupBusy && !accessRevoked }
    return !phoneSetupBusy && (!nativeConfigured || nativeCommandReady)
  }
  private var nativeReceiverBound: Bool {
    phoneProfile?.profile.phase != .retired && phoneProfile?.profile.nativeReceiver != nil
  }

  public init(
    service: MessagingService, credentials: any NessaCredentialStoring,
    preferences: any ChatPreferences, snapshots: PhoneSnapshotSession? = nil,
    recovery: ConnectionRecovery? = nil, phoneSync: (any PhoneSyncRunning)? = nil,
    conversationSharing: PhoneConversationSharing? = nil, phoneChat: PhoneProductChat? = nil
  ) {
    self.credentials = credentials
    self.service = service
    self.preferences = preferences
    let preference = preferences.strings(forKey: Self.automaticConnectionKey)
    automaticConnectionEnabled = preference == nil || preference == ["enabled"]
    self.snapshots = snapshots
    self.recovery = recovery
    self.phoneSync = phoneSync
    self.phoneChat = phoneChat
    self.conversationSharing = conversationSharing
  }
  deinit {
    recoveryTask?.cancel()
    for read in previewReads.values { read.task.cancel() }
  }
  /// The model owns admission and settlement; a dismissed sheet is only an observer.
  @discardableResult public func performPhoneSetup(_ operation: PhoneSetupOperation) async -> Bool {
    await performPhoneAction(.setup(operation))
  }
  @discardableResult public func performConversationSharing(
    _ operation: PhoneConversationSharingOperation
  ) async -> Bool {
    guard conversationSharing != nil else { return false }
    return await performPhoneAction(.sharing(operation))
  }
  private enum PhoneAction: Sendable {
    case setup(PhoneSetupOperation)
    case sharing(PhoneConversationSharingOperation)
    var requiresProductConnection: Bool {
      if case .setup(let operation) = self { return operation.requiresProductConnection }
      return true
    }
    var conversationID: String? {
      guard case .sharing(let operation) = self else { return nil }
      switch operation {
      case .share(let id): return id
      case .check(let intent), .retry(let intent): return intent.conversationID
      case .choices: return nil
      }
    }
  }
  private func performPhoneAction(_ operation: PhoneAction) async -> Bool {
    guard !Task.isCancelled, let phoneSync, foreground, !busy, !sending,
      phoneSetupTask == nil
    else { return false }
    if operation.requiresProductConnection {
      guard connected, acceptedLease != nil, profile != nil else { return false }
    }
    let original = profile
    let oldSnapshot = phoneProfile
    let oldOfflineEligible = nativeOfflineEligible
    let context = PhoneSetupContext(
      connection: original.map {
        PhoneProductConnection(
          address: $0.address, credential: $0.credential, instance: $0.instance)
      }, lease: acceptedLease, snapshot: oldSnapshot)
    let token = UUID()
    generation += 1
    let expected = generation
    // Sharing keeps this account and draft scope. Restart its feeds after settlement,
    // so the visible chat and its sheet remain owned during the operation.
    if case .setup = operation {
      connectionRevision += 1
      deliveryScopeRevision += 1
    }
    phoneSetupToken = token
    phoneSetupBusy = true
    nativeConfigured = true
    nativeHistoryReady = false
    nativeCommandReady = false
    nativeOfflineEligible = false
    nativeReadRequested = false
    nativeReadTargets = []
    snapshotLease = nil
    cancelPreviews()
    conversations = []
    views = [:]
    previewViews = [:]
    viewCursors = [:]
    readVersions = [:]
    unlistedCreations = [:]
    unavailableNativeIDs = []
    pendingDeletionIDs = []
    if case .setup = operation {
      pendingCommands = []
      pendingLoadError = nil
      commandActions = [:]
      checkingCommands = []
      acknowledgedCommands = []
      acknowledgmentOrder = []
    }
    phoneInvitations = []
    phoneSharingMessage = nil
    if case .setup = operation {
      phoneOwnerChoices = nil
      pendingPhoneShares = []
      phoneSharingFailure = nil
    }
    let startup = phoneStartupTask
    let read = nativeReadTask
    let task = Task { [weak self] in
      guard let self else { return false }
      defer {
        if self.phoneSetupToken == token {
          self.phoneSetupToken = nil
          self.phoneSetupTask = nil
          self.phoneSetupBusy = false
          if case .sharing = operation, self.generation == expected, self.foreground,
            self.profile == original, self.acceptedLease == context.lease
          {
            self.connectionRevision += 1
          }
          if !self.connected { self.startRecovery() }
        }
      }
      _ = try? await startup?.value
      await read?.value
      do {
        let current: @Sendable () async throws -> Void = { [weak self] in
          guard let self else { throw PhoneSetupRefusal.changed }
          try await self.checkPhoneSetup(
            token, generation: expected, original: original, context: context,
            needsConnection: operation.requiresProductConnection)
        }
        let result: PhoneSetupResult
        let shared: PhoneConversationSharingResult?
        switch operation {
        case .setup(let choice):
          shared = nil
          result = try await PhoneSetupActions(service: self.service, sync: phoneSync)
            .perform(choice, context: context, current: current)
        case .sharing(let choice):
          guard let sharing = self.conversationSharing else { throw PhoneSetupRefusal.unavailable }
          let value = try await sharing.perform(choice, context: context, current: current)
          shared = value
          result = .init(snapshot: value.snapshot)
        }
        try self.checkPhoneSetup(
          token, generation: expected, original: original, context: context,
          needsConnection: operation.requiresProductConnection)
        self.phoneProfile = result.snapshot
        self.nativeNeedsRestore = false
        self.phoneInvitations = result.invitations ?? []
        self.phoneSyncFailure = nil
        self.phoneSyncError = nil
        if let shared {
          if let choices = shared.choices { self.phoneOwnerChoices = choices }
          if let grants = shared.shares,
            let credential = shared.snapshot.profile.pairingStatus?.credentialID
          {
            self.phoneSharingMessage =
              grants.contains {
                $0.credentialId.utf8.elementsEqual(credential.utf8)
              } ? "Read access enabled." : "Not shared with this phone."
          }
          self.phoneSharingFailure = nil
        }
        if let selected = result.snapshot?.profile {
          if case .setup(.prepare) = operation, let original {
            self.nativeOfflineEligible =
              selected.productAddress.utf8.elementsEqual(original.address.utf8)
              && selected.instance.utf8.elementsEqual(original.instance.utf8)
          } else {
            self.nativeOfflineEligible =
              oldOfflineEligible
              && oldSnapshot?.profile.sameSetup(as: selected) == true
          }
        }
        if self.nativeReceiverBound {
          await self.loadNativeDisplay(
            operation.conversationID.map { [$0] } ?? [], admittedSetup: token)
        }
        await self.refreshPhoneShareIntents(generation: expected)
        guard self.generation == expected, self.foreground else { return false }
        await self.refreshPendingCommands()
        try self.checkPhoneSetup(
          token, generation: expected, original: original, context: context,
          needsConnection: operation.requiresProductConnection)
        return true
      } catch {
        guard self.generation == expected, self.foreground,
          self.phoneSetupToken == token, self.profile == original
        else { return false }
        self.phoneSyncFailure = error
        if case .sharing = operation {
          self.phoneSharingFailure = error
          self.phoneSharingMessage = "Sharing needs attention. Check or retry the original request."
          await self.refreshPhoneShareIntents(generation: expected)
          guard self.generation == expected, self.foreground, self.profile == original else {
            return false
          }
        }
        self.phoneSyncError = "Phone sync needs attention."
        // Metadata is recovery information, never a substitute for admitted native history.
        if let registry = try? await phoneSync.savedProfiles(),
          self.generation == expected, self.foreground, self.profile == original
        {
          let captured =
            (error as? PhoneSetupFailure)?.snapshot
            ?? (error as? PhoneConversationSharingFailure)?.snapshot
          var underlying: any Error = error
          if let setup = underlying as? PhoneSetupFailure { underlying = setup.underlying }
          if let sharing = underlying as? PhoneConversationSharingFailure {
            underlying = sharing.underlying
          }
          if let runtime = underlying as? PhoneSyncRuntimeFailure {
            underlying = runtime.underlying
          }
          let coordination = underlying as? PhoneProfileCoordinationFailure
          let selected = registry.profiles.first { $0.id == registry.selected }
          let same = selected.map { captured?.profile.sameSetup(as: $0) == true } ?? false
          let failureMatches = coordination?.profileID == registry.selected
          self.phoneProfile = try? PhoneProfileSnapshot(
            registry: registry,
            local: failureMatches ? coordination?.local : (same ? captured?.local : nil),
            nativeStatus: failureMatches
              ? coordination?.nativeStatus
              : (same ? captured?.nativeStatus : nil),
            source: failureMatches ? coordination?.source : (same ? captured?.source : nil),
            activationStopped: same ? captured?.activationStopped : nil,
            nativeRefresh: failureMatches
              ? coordination?.nativeRefresh
              : (same ? captured?.nativeRefresh : nil))
        }
        return false
      }
    }
    phoneSetupTask = task
    return await task.value
  }
  private func refreshPhoneShareIntents(generation expected: Int) async {
    guard let conversationSharing, let selected = phoneProfile?.profile, foreground else { return }
    do {
      let values = try await conversationSharing.pending(profileID: selected.id)
      guard generation == expected, foreground,
        phoneProfile?.profile.sameSetup(as: selected) == true
      else { return }
      pendingPhoneShares = values
      phoneSharingLoadError = nil
    } catch {
      guard generation == expected, foreground,
        phoneProfile?.profile.sameSetup(as: selected) == true
      else { return }
      pendingPhoneShares = []
      phoneSharingLoadError = "Saved sharing requests unavailable."
      phoneSharingFailure = error
    }
  }
  private func clearPhoneSharing() {
    phoneOwnerChoices = nil
    pendingPhoneShares = []
    phoneSharingMessage = nil
    phoneSharingLoadError = nil
    phoneSharingFailure = nil
  }
  private func checkPhoneSetup(
    _ token: UUID, generation expected: Int, original: Profile?, context: PhoneSetupContext,
    needsConnection: Bool
  ) throws {
    guard foreground, generation == expected, phoneSetupToken == token,
      profile == original, acceptedLease == context.lease,
      !needsConnection || connected
    else { throw PhoneSetupRefusal.changed }
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
    let turns = views[conversation]?.messages ?? []
    let targets = replies(in: conversation)
    // Hydration can replace a view without a live apply. Reuse requires the
    // same inputs, including the initially absent history and saved reply links.
    if let cached = replyProjections[conversation], cached.name == name,
      cached.turns == turns, cached.targets == targets
    {
      return cached.value
    }
    let value = ConversationReplies(
      turns: turns, targets: targets, agentName: name)
    replyProjections[conversation] = ReplyProjection(
      name: name, turns: turns, targets: targets, value: value)
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
  /// Reads the gateway's archived chats for the Archived list.
  public func loadArchived() async {
    guard connected else { return }
    let expected = generation
    do {
      let list = try await service.listArchived()
      guard generation == expected else { return }
      archivedConversations = list.conversations.filter {
        !deletedIDs.contains($0.id) && !pendingDeletionIDs.contains($0.id)
      }
      let listed = Set(conversations.map(\.id))
      let missing = archivedConversations.filter { !listed.contains($0.id) }
      if !missing.isEmpty { conversations += missing }
    } catch {
      guard generation == expected else { return }
      self.error = error.localizedDescription
    }
  }
  /// Archives or unarchives a chat on the gateway, then moves its row between the lists.
  /// The inbox feed and the next archived read agree once the gateway has applied it.
  public func setArchived(_ archived: Bool, conversationID: String) async {
    guard connected else {
      error = NessaGatewayError.disconnected.localizedDescription
      return
    }
    let expected = generation
    do {
      try await service.setArchived(archived, conversationID: conversationID)
    } catch {
      guard generation == expected else { return }
      self.error = error.localizedDescription
      return
    }
    guard generation == expected else { return }
    if archived {
      if let row = conversations.first(where: { $0.id == conversationID }),
        !archivedConversations.contains(where: { $0.id == conversationID })
      {
        archivedConversations.insert(row, at: 0)
      }
      if isPinned(conversationID) { togglePin(conversationID) }
    } else {
      archivedConversations.removeAll { $0.id == conversationID }
    }
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
  public func previewState(for identifier: String) -> PreviewState {
    guard let id = existingConversationID(for: identifier), !isDeleting(identifier),
      !deletedIDs.contains(id)
    else { return .unavailable }
    if let view = views[id] ?? previewViews[id] {
      return view.messages.isEmpty ? .empty : .available(view)
    }
    return loadingPreviews.contains(id) ? .loading : .unavailable
  }
  public func loadPreview(_ identifier: String) async {
    guard let id = existingConversationID(for: identifier), !isDeleting(identifier),
      !deletedIDs.contains(id), views[id] == nil, previewViews[id] == nil
    else { return }
    if let read = previewReads[id] {
      await read.task.value
      return
    }
    if nativeConfigured {
      guard nativeReceiverBound else { return }
      await loadNativeDisplay([id])
      return
    }
    guard connected else { return }
    let expected = generation
    let version = readVersions[id] ?? 0
    let token = UUID()
    // The model owns this read; dismissing one observer must not cancel another.
    let task = Task { [weak self, service] in
      do {
        let result = try await service.read(id)
        self?.finishPreview(result, id: id, token: token, generation: expected, version: version)
      } catch {
        self?.finishPreview(nil, id: id, token: token, generation: expected, version: version)
      }
    }
    previewReads[id] = PreviewRead(token: token, task: task)
    loadingPreviews.insert(id)
    await task.value
  }
  private func finishPreview(
    _ result: NessaConversationView?, id: String, token: UUID, generation expected: Int,
    version: Int
  ) {
    guard previewReads[id]?.token == token else { return }
    previewReads.removeValue(forKey: id)
    loadingPreviews.remove(id)
    guard generation == expected, !Task.isCancelled, !deletedIDs.contains(id),
      !pendingDeletionIDs.contains(id), (readVersions[id] ?? 0) == version,
      let result, result.conversationId == id
    else { return }
    previewViews[id] = result
  }
  private func cancelPreviews(_ id: String? = nil) {
    if let id {
      previewReads.removeValue(forKey: id)?.task.cancel()
      loadingPreviews.remove(id)
    } else {
      let reads = previewReads.values
      previewReads = [:]
      loadingPreviews = []
      for read in reads { read.task.cancel() }
    }
  }
  public func existingConversationID(for identifier: String) -> String? {
    conversations.contains { $0.id == identifier } ? identifier : agentThreads[identifier]
  }
  public func chatName(_ id: String) -> String {
    conversations.first { $0.id == id }?.title ?? agentName(for: id)
  }
  public func hasConversation(_ agent: String) -> Bool { existingConversationID(for: agent) != nil }
  public func deleteConversation(for agent: String) async {
    let token = UUID()
    let task = Task { await self.performDeleteConversation(for: agent) }
    deletionDrains[token] = task
    await task.value
    deletionDrains.removeValue(forKey: token)
  }
  private func performDeleteConversation(for agent: String) async {
    guard connected, conversationAuthorityReady, let id = existingConversationID(for: agent) else {
      return
    }
    let currentGeneration = generation
    guard await validateNativeCommand(id, generation: currentGeneration) else { return }
    pendingDeletionIDs.insert(id)
    cancelPreviews(id)
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
        if nativeConfigured {
          await loadNativeDisplay([id])
          return
        }
        do { _ = try await service.read(id) } catch {
          let behavior = (error as? GatewayProductRejection)?.behavior ?? error as? NessaGatewayError
          if case .conversationNotFound = behavior, generation == currentGeneration {
            await removeDeletedConversation(id, identifier: agent)
          }
          // An uncertain read preserves the cached chat and preferences.
        }
      }
    }
  }
  private func removeDeletedConversation(_ id: String, identifier agent: String) async {
    let identifiers = Set(agentThreads.compactMap { $0.value == id ? $0.key : nil } + [id, agent])
    deletedIDs.insert(id)
    unlistedCreations.removeValue(forKey: id)
    listVersion += 1
    readVersions[id, default: 0] += 1
    conversationAgents.removeValue(forKey: id)
    preferences.save(conversationAgents, forKey: identityKey)
    agentThreads = agentThreads.filter { $0.value != id }
    preferences.save(agentThreads, forKey: threadKey)
    previewViews.removeValue(forKey: id)
    unreadChats.removeAll { identifiers.contains($0) }
    mutedChats.removeAll { identifiers.contains($0) }
    archivedConversations.removeAll { $0.id == id }
    saveStatus()
    for identifier in identifiers where isPinned(identifier) { togglePin(identifier) }
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
  public var hasSavedConnection: Bool {
    savedReconnectGatewayAddress != nil
  }
  public var savedReconnectGatewayAddress: String? {
    if let originalConnection { return originalConnection.address }
    if let saved = phoneProfile?.profile { return saved.productAddress }
    guard let saved = preferences.mapping(forKey: Self.savedConnectionKey),
      let address = saved["address"], saved["instance"] != nil,
      !(credentials.load() ?? "").isEmpty
    else { return nil }
    return address
  }
  private func setAutomaticConnection(_ enabled: Bool) {
    automaticConnectionEnabled = enabled
    preferences.save([enabled ? "enabled" : "disabled"], forKey: Self.automaticConnectionKey)
  }
  public func reconnectSavedConnection() async {
    if let originalConnection {
      await connect(
        address: originalConnection.address, credential: originalConnection.credential,
        instance: originalConnection.instance)
    } else if let saved = phoneProfile?.profile {
      await connect(
        address: saved.productAddress, credential: "", instance: saved.instance,
        restoringSavedProfile: true)
    } else if let saved = preferences.mapping(forKey: Self.savedConnectionKey),
      let address = saved["address"], let instance = saved["instance"],
      let credential = credentials.load(), !credential.isEmpty
    {
      await connect(address: address, credential: credential, instance: instance)
    }
  }
  /// Persist local network intent, then retain one physical retirement owner.
  public func manualDisconnect() async {
    setAutomaticConnection(false)
    await retireConnection(background: false)
  }

  private func restoreDisconnectedHistory() async {
    await retirementTask?.value
    guard foreground, !automaticConnectionEnabled else { return }
    generation += 1
    let expected = generation
    busy = true
    defer { if generation == expected { busy = false } }
    connected = false
    acceptedLease = nil
    nativeCommandReady = false
    do {
      if let phoneSync {
        nativeConfigured = true
        snapshotLease = nil
        let startupToken = UUID()
        let startup = Task { try await phoneSync.passiveStartup() }
        phoneStartupTask = startup
        phoneStartupToken = startupToken
        defer {
          if phoneStartupToken == startupToken {
            phoneStartupTask = nil
            phoneStartupToken = nil
          }
        }
        let restored = try await startup.value
        guard generation == expected, foreground, !automaticConnectionEnabled else { return }
        adoptPassiveSnapshot(restored?.snapshot, connection: restored?.connection)
        nativeConfigured = restored != nil
        nativeNeedsRestore = false
        if let connection = restored?.connection {
          let selected = Profile(
            address: connection.address, credential: connection.credential,
            instance: connection.instance)
          profile = selected
          originalConnection = selected
          nativeOfflineEligible = true
          loadPreferences(selected)
          await loadPassiveNativeDisplay()
          return
        }
        if nativeConfigured { return }
      }
      let selected: Profile?
      if let originalConnection {
        selected = originalConnection
      } else if let saved = preferences.mapping(forKey: Self.savedConnectionKey),
        let address = saved["address"], let instance = saved["instance"],
        let credential = credentials.load(), !credential.isEmpty
      {
        selected = Profile(address: address, credential: credential, instance: instance)
      } else {
        selected = nil
      }
      guard let selected else { return }
      profile = selected
      originalConnection = selected
      loadPreferences(selected)
      try await hydrate(selected, generation: expected)
    } catch {
      guard generation == expected, foreground else { return }
      phoneSyncFailure = error
      phoneSyncError = "Saved chats unavailable."
      if let phoneSync, let registry = try? await phoneSync.savedProfiles(), generation == expected,
        foreground
      {
        let saved = try? PhoneProfileSnapshot(
          registry: registry, local: nil, nativeStatus: nil, source: nil)
        adoptPassiveSnapshot(saved, connection: nil)
      }
    }
  }

  private func adoptPassiveSnapshot(
    _ snapshot: PhoneProfileSnapshot?, connection: PhoneProductConnection?
  ) {
    let selected = connection.map {
      Profile(address: $0.address, credential: $0.credential, instance: $0.instance)
    }
    let previous = phoneProfile?.profile
    let next = snapshot?.profile
    let sameNative =
      previous.map { old in
        next.map {
          old.sameSetup(as: $0) && old.phase == $0.phase
            && old.hasRetirementEvidence == $0.hasRetirementEvidence
            && PhonePairingCorrelation.equal(old.nativeReceiver ?? "", $0.nativeReceiver ?? "")
        } ?? false
      } ?? (next == nil)
    let sameIssued =
      phoneProfile?.local == snapshot?.local
      && PhonePairingCorrelation.equal(
        phoneProfile?.local?.issued?.credential ?? "", snapshot?.local?.issued?.credential ?? "")
      && PhonePairingCorrelation.equal(
        phoneProfile?.local?.issued?.receiver ?? "", snapshot?.local?.issued?.receiver ?? "")
    if !sameNative || !sameIssued || (next != nil && profile != selected) {
      deliveryScopeRevision += 1
      cancelPreviews()
      clearPhoneSharing()
      nativeOfflineEligible = false
      conversations = []
      views = [:]
      previewViews = [:]
      replyProjections = [:]
      viewCursors = [:]
      readVersions = [:]
      unlistedCreations = [:]
      unavailableNativeIDs = []
      deletedIDs = []
      pendingDeletionIDs = []
      pendingCommands = []
      pendingLoadError = nil
      acknowledgedCommands = []
      acknowledgmentOrder = []
      commandActions = [:]
      checkingCommands = []
      pinnedChats = []
      unreadChats = []
      mutedChats = []
      archivedConversations = []
      reactions = [:]
      replyTargets = [:]
      agentProfiles = []
      conversationAgents = [:]
      agentThreads = [:]
      profile = nil
      originalConnection = nil
      snapshotLease = nil
      nativeHistoryReady = false
      nativeCommandReady = false
    }
    phoneProfile = snapshot
  }

  private func loadPassiveNativeDisplay(_ targets: Set<String> = []) async {
    guard !automaticConnectionEnabled, !connected, foreground, let phoneSync, nativeReceiverBound
    else { return }
    if nativeNeedsRestore {
      await restoreDisconnectedHistory()
      guard !nativeNeedsRestore, nativeConfigured, nativeReceiverBound else { return }
    }
    if let current = nativeReadTask { await current.value }
    guard !automaticConnectionEnabled, !connected, foreground else { return }
    let expected = generation
    let token = UUID()
    let task = Task { [weak self] in
      guard let self else { return }
      await self.performPassiveNativeDisplay(phoneSync, targets: targets, expected: expected)
      if self.nativeReadToken == token {
        self.nativeReadTask = nil
        self.nativeReadToken = nil
      }
    }
    nativeReadToken = token
    nativeReadTask = task
    await task.value
  }

  private func performPassiveNativeDisplay(
    _ phoneSync: any PhoneSyncRunning, targets: Set<String>, expected: Int
  ) async {
    do {
      let result = try await phoneSync.passiveDisplay(
        conversations: Array(targets.sorted().prefix(20)), revision: UUID())
      guard generation == expected, foreground, !automaticConnectionEnabled, !connected else {
        return
      }
      phoneProfile = result.snapshot
      nativeHistoryReady = true
      nativeCommandReady = false
      phoneSyncFailure = nil
      phoneSyncError = nil
      for id in result.catalogue.pages.flatMap({ $0.entries.filter(\.deleted).map { $0.key.id } }) {
        await removeDeletedConversation(id, identifier: id)
        guard generation == expected, foreground, !automaticConnectionEnabled, !connected else {
          return
        }
      }
      guard generation == expected, foreground, !automaticConnectionEnabled, !connected else {
        return
      }
      _ = applyList(result.catalogue.list)
      for (id, read) in result.transcripts {
        guard !deletedIDs.contains(id), !pendingDeletionIDs.contains(id) else { continue }
        switch read {
        case .available(let value):
          if case .available(let projection) = value.value.view {
            unavailableNativeIDs.remove(id)
            apply(projection.display, to: id)
          }
        case .failed(let failure):
          unavailableNativeIDs.insert(id)
          views.removeValue(forKey: id)
          previewViews.removeValue(forKey: id)
          replyProjections.removeValue(forKey: id)
          phoneSyncFailure = failure
          phoneSyncError = "Saved conversation unavailable."
        }
      }
    } catch {
      guard generation == expected, foreground else { return }
      nativeHistoryReady = false
      nativeCommandReady = false
      conversations = []
      views = [:]
      previewViews = [:]
      replyProjections = [:]
      phoneSyncFailure = error
      phoneSyncError = "Saved chats unavailable."
    }
  }

  public func savedCredential() -> String { credentials.load() ?? "" }
  /// Connect to the paired Mac over its native link: the whole product
  /// session, as the owner's phone, with no gateway address or credential.
  func connectLinked(
    _ desktop: LinkedDesktop, instance: String, products: any LinkedProductOpening
  ) async {
    linkedDesktop = desktop
    linkedProducts = products
    await connect(
      Profile(address: desktop.address, credential: "", instance: instance, linked: desktop.id),
      restoringSavedProfile: false, automatically: false)
  }
  /// Try the paired Mac again after its connection failed.
  public func reconnectLinked() async {
    guard let desktop = linkedDesktop, let products = linkedProducts, !connected else { return }
    await connectLinked(desktop, instance: profile?.instance ?? "", products: products)
  }
  /// Close the linked connection and wait until its native session let go of
  /// the Mac's directory, so that directory can be removed.
  public func forgetLinked() async {
    guard profile?.linked != nil else { return }
    await manualDisconnect()
    linkedDesktop = nil
    linkedProducts = nil
    try? await service.drainLinked()
  }
  public func connect(
    address: String, credential: String, instance: String,
    restoringSavedProfile: Bool = false, automatically: Bool = false
  ) async {
    await connect(
      Profile(address: address, credential: credential, instance: instance),
      restoringSavedProfile: restoringSavedProfile, automatically: automatically)
  }
  private func connect(
    _ requested: Profile, restoringSavedProfile: Bool, automatically: Bool
  ) async {
    let (address, instance) = (requested.address, requested.instance)
    if automatically && !automaticConnectionEnabled {
      await restoreDisconnectedHistory()
      return
    }
    if !automatically {
      setAutomaticConnection(true)
      accessRevoked = false
    }
    recoveryTask?.cancel()
    recoveryTask = nil
    reconnecting = false
    var next = requested
    if profile != next {
      deliveryScopeRevision += 1
      acknowledgedCommands = []
      acknowledgmentOrder = []
      accessRevoked = false
      phoneDeliveries = []
    }
    profile = next
    cancelPreviews()
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
    acceptedLease = nil
    nativeHistoryReady = false
    nativeCommandReady = false
    nativeOfflineEligible = false
    clearPhoneSharing()
    nativeReadRequested = false
    nativeReadTargets = []
    unavailableNativeIDs = []
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
    archivedConversations = []
    reactions = [:]
    replyTargets = [:]
    replyProjections = [:]
    previewViews = [:]
    conversationAgents = [:]
    agentThreads = [:]
    deletedIDs = []
    pendingDeletionIDs = []
    views = [:]
    readVersions = [:]
    viewCursors = [:]
    unlistedCreations = [:]
    do {
      if phoneSync != nil { await retirementTask?.value }
      _ = try? await phoneStartupTask?.value
      _ = await phoneSetupTask?.value
      await nativeReadTask?.value
      guard generation == expected, foreground, !Task.isCancelled else { return }
      let restored = try await restorePhone(generation: expected)
      guard generation == expected, foreground, !Task.isCancelled else { return }
      if restoringSavedProfile {
        if let connection = restored?.connection {
          next = Profile(
            address: connection.address, credential: connection.credential,
            instance: connection.instance)
          profile = next
        } else if nativeConfigured {
          phoneSyncError = "Phone sync needs setup."
          return
        } else {
          let savedCredential = self.savedCredential()
          if savedCredential.isEmpty { return }
          next = Profile(address: address, credential: savedCredential, instance: instance)
          profile = next
        }
      }
      if let connection = restored?.connection {
        nativeOfflineEligible =
          connection.address.utf8.elementsEqual(next.address.utf8)
          && connection.credential.utf8.elementsEqual(next.credential.utf8)
          && connection.instance.utf8.elementsEqual(next.instance.utf8)
      }
      loadPreferences(next)
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
  private func restorePhone(generation expected: Int) async throws -> PhoneSyncStartup? {
    guard let phoneSync else {
      nativeNeedsRestore = false
      return nil
    }
    nativeConfigured = true  // No legacy read while registry absence is unproven.
    let token: UUID
    let task: Task<PhoneSyncStartup?, Error>
    if let existing = phoneStartupTask, let existingToken = phoneStartupToken {
      task = existing
      token = existingToken
    } else {
      token = UUID()
      task = Task { try await phoneSync.startup() }
      phoneStartupTask = task
      phoneStartupToken = token
    }
    defer {
      if phoneStartupToken == token {
        phoneStartupTask = nil
        phoneStartupToken = nil
      }
    }
    do {
      let result = try await task.value
      guard generation == expected, foreground, !Task.isCancelled else { throw CancellationError() }
      phoneProfile = result?.snapshot
      nativeConfigured = result != nil
      nativeNeedsRestore = false
      phoneSyncError = nil
      phoneSyncFailure = nil
      return result
    } catch {
      guard generation == expected, foreground, !Task.isCancelled else { throw CancellationError() }
      nativeHistoryReady = false
      nativeCommandReady = false
      phoneSyncError = "Phone sync needs attention."
      phoneSyncFailure = error
      // Passive recovery metadata never enables history or a legacy fallback.
      if let registry = try? await phoneSync.savedProfiles() {
        guard generation == expected, foreground else { throw CancellationError() }
        phoneProfile = try PhoneProfileSnapshot(
          registry: registry, local: nil,
          nativeStatus: nil, source: nil)
        nativeNeedsRestore = false
        return nil
      }
      throw error
    }
  }

  private func loadNativeDisplay(
    _ targets: Set<String> = [], admittedSetup: UUID? = nil
  ) async {
    guard !phoneSetupBusy || (admittedSetup != nil && admittedSetup == phoneSetupToken),
      let phoneSync, nativeReceiverBound,
      acceptedLease != nil || nativeOfflineEligible
    else { return }
    nativeReadTargets.formUnion(targets)
    nativeReadRequested = true
    if let task = nativeReadTask {
      await task.value
      return
    }
    let expected = generation
    let token = UUID()
    nativeReadToken = token
    let task = Task { [weak self] in
      guard let self else { return }
      defer {
        if self.nativeReadToken == token {
          self.nativeReadTask = nil
          self.nativeReadToken = nil
        }
      }
      while self.generation == expected, self.nativeReadRequested, self.foreground {
        let ids = Array(self.nativeReadTargets.sorted().prefix(20))
        self.nativeReadTargets.subtract(ids)
        self.nativeReadRequested = !self.nativeReadTargets.isEmpty
        let epoch = UUID()
        do {
          let result = try await phoneSync.display(
            on: self.acceptedLease,
            conversations: ids, revision: epoch)
          guard self.generation == expected, self.foreground else { return }
          self.phoneProfile = result.snapshot
          self.phoneSyncFailure = result.refreshFailure
          self.nativeCommandReady = result.commandReady(on: self.acceptedLease)
          self.phoneSyncError =
            self.nativeCommandReady ? nil : "Showing saved chats; sync unavailable."
          self.nativeHistoryReady = true
          // Access withdrawal removes display owners, not the conversation's identity or preferences.
          for id in result.snapshot.nativeRefresh?.read?.withdrawn ?? [] {
            self.withdrawNativeDisplay(id)
          }
          let deleted = Set(
            result.catalogue.pages.flatMap {
              $0.entries.filter(\.deleted).map { $0.key.id }
            })
          for id in deleted {
            guard self.generation == expected, self.foreground else { return }
            await self.removeDeletedConversation(id, identifier: id)
          }
          guard self.generation == expected, self.foreground else { return }
          _ = self.applyList(result.catalogue.list)
          for (id, read) in result.transcripts {
            guard !self.deletedIDs.contains(id), !self.pendingDeletionIDs.contains(id) else {
              continue
            }
            switch read {
            case .available(let captured):
              if case .available(let value) = captured.value.view {
                self.unavailableNativeIDs.remove(id)
                self.apply(value.display, to: id)
              }
            case .failed(let failure):
              self.phoneSyncFailure = failure
              self.unavailableNativeIDs.insert(id)
              self.views.removeValue(forKey: id)
              self.previewViews.removeValue(forKey: id)
              self.replyProjections.removeValue(forKey: id)
              self.phoneSyncError = "Conversation unavailable."
            }
          }
        } catch {
          guard self.generation == expected, self.foreground else { return }
          if let failure = error as? PhoneSyncRuntimeFailure, let snapshot = failure.snapshot {
            self.phoneProfile = snapshot
          }
          self.nativeHistoryReady = false
          self.nativeCommandReady = false
          self.phoneSyncFailure = error
          self.conversations = []
          self.views = [:]
          self.previewViews = [:]
          self.replyProjections = [:]
          self.phoneSyncError = "Phone sync unavailable."
          if self.phoneProfile?.profile.phase == .retired {
            let obsolete = self.acceptedLease
            self.acceptedLease = nil
            self.connected = false
            await self.service.retire(obsolete)
          }
          return
        }
      }
    }
    nativeReadTask = task
    await task.value
  }

  private func withdrawNativeDisplay(_ id: String) {
    cancelPreviews(id)
    readVersions[id, default: 0] += 1
    viewCursors.removeValue(forKey: id)
    unlistedCreations.removeValue(forKey: id)
    conversations.removeAll { $0.id == id }
    views.removeValue(forKey: id)
    previewViews.removeValue(forKey: id)
    replyProjections.removeValue(forKey: id)
    unavailableNativeIDs.insert(id)
  }

  private func validateNativeCommand(_ id: String?, generation expected: Int) async -> Bool {
    if phoneChat != nil { return generation == expected && connected && !accessRevoked }
    guard nativeConfigured else { return generation == expected && connected }
    guard !phoneSetupBusy, acceptedLease != nil, nativeReceiverBound else { return false }
    await loadNativeDisplay(id.map { [$0] } ?? [])
    return generation == expected && foreground && connected && acceptedLease != nil
      && nativeCommandReady && (id.map { !unavailableNativeIDs.contains($0) } ?? true)
  }

  private func hydrate(_ profile: Profile, generation expected: Int) async throws {
    if nativeConfigured && phoneChat == nil {
      if nativeReceiverBound { await loadNativeDisplay() }
      return
    }
    guard let snapshots else { return }
    let (lease, saved) = try await snapshots.prepare(cacheScope(profile))
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
    archivedConversations = []
    previewViews = [:]
    let savedPins = preferences.strings(forKey: pinKey) ?? []
    pinnedChats = NessaPinPolicy.normalize(savedPins)
    preferences.save(pinnedChats, forKey: pinKey)
    agentThreads = preferences.mapping(forKey: threadKey) ?? [:]
  }
  private func dial(_ profile: Profile, generation expected: Int) async throws {
    await retirementTask?.value
    guard generation == expected, foreground, !Task.isCancelled else { throw CancellationError() }
    if nativeNeedsRestore {
      let saved = try await restorePhone(generation: expected)
      if let connection = saved?.connection {
        guard connection.address.utf8.elementsEqual(profile.address.utf8),
          connection.credential.utf8.elementsEqual(profile.credential.utf8),
          connection.instance.utf8.elementsEqual(profile.instance.utf8)
        else { throw PhoneProfileCoordinationRefusal.accountChanged }
        nativeOfflineEligible = true
      }
      if nativeReceiverBound && phoneChat == nil { await loadNativeDisplay() }
    }
    if snapshotLease == nil && !nativeConfigured {
      try await hydrate(profile, generation: expected)
    }
    guard generation == expected, foreground, !Task.isCancelled else { throw CancellationError() }
    var receipt: GatewayConnectionLease?
    do {
      if let linked = profile.linked {
        guard let desktop = linkedDesktop, desktop.id == linked, let products = linkedProducts
        else { throw NessaGatewayError.disconnected }
        let exchange = try await products.open(desktop, instance: profile.instance)
        receipt = try await service.connectLinked(exchange, scope: cacheScope(profile))
      } else {
        receipt = try await service.connect(
          address: profile.address, credential: profile.credential, instance: profile.instance)
      }
      guard generation == expected, foreground, !Task.isCancelled else { throw CancellationError() }
      acceptedLease = receipt
      let agents = try await service.agents()
      guard generation == expected, !Task.isCancelled else { throw CancellationError() }
      agentProfiles = agents
      try await refreshList()
      guard generation == expected, foreground, !Task.isCancelled else { throw CancellationError() }
      if let receipt, acceptedLease != receipt { throw PhoneProfileCoordinationRefusal.retired }
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
      // A linked Mac has no credential of its own to keep.
      if !nativeConfigured && profile.linked == nil {
        try credentials.save(profile.credential)
        preferences.save(
          ["address": profile.address, "instance": profile.instance],
          forKey: Self.savedConnectionKey)
      }
      originalConnection = profile
      connected = true
      if let phoneChat {
        do {
          await phoneChat.activate(cacheScope(profile))
          let recovered = try await phoneChat.recover()
          phoneDeliveries = try await phoneChat.list()
          noteRevokedDeliveries(recovered)
        } catch {
          self.error = "Saved sends could not be read."
        }
      }
      await refreshPhoneShareIntents(generation: expected)
      guard generation == expected, foreground, !Task.isCancelled else { throw CancellationError() }
      connectionRevision += 1
    } catch {
      if generation == expected { acceptedLease = nil }
      await service.retire(receipt)
      throw error
    }
  }
  /// Actual background changes foreground authority; local Disconnect does not.
  public func suspendConnection() async { await retireConnection(background: true) }
  private func retireConnection(background: Bool) async {
    if background { foreground = false }
    let capturedLease = acceptedLease
    let setup = phoneSetupTask
    let startup = phoneStartupTask
    let read = nativeReadTask
    let deletes = Array(deletionDrains.values)
    clearPhoneSharing()
    acceptedLease = nil
    nativeHistoryReady = false
    nativeCommandReady = false
    nativeNeedsRestore = true
    nativeReadRequested = false
    nativeReadTargets = []
    cancelPreviews()
    generation += 1
    let expected = generation
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
    let service = service
    let phoneSync = phoneSync
    let prior = retirementTask
    let retirement = Task { [weak self] in
      await prior?.value
      async let product: Void =
        capturedLease != nil ? service.retire(capturedLease) : service.disconnect()
      do { try await phoneSync?.suspend() } catch {
        if let self, self.generation == expected {
          self.phoneSyncFailure = error
          self.phoneSyncError = "Phone sync could not close."
        }
      }
      await product
      _ = try? await startup?.value
      await read?.value
      _ = await setup?.value
      for task in deletes { await task.value }
    }
    retirementTask = retirement
    await retirement.value
    let snapshots = snapshots
    Task { await snapshots?.flush() }
  }
  public func resumeConnection() {
    foreground = true
    if automaticConnectionEnabled && !connected { startRecovery() }
  }
  private func startRecovery() {
    guard !accessRevoked, automaticConnectionEnabled, !phoneSetupBusy, let recovery, let profile,
      foreground,
      recoveryTask == nil,
      manualAttempt == nil
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
    if phoneChat != nil && PhoneAccess.revoked(error) {
      accessRevoked = true
      setAutomaticConnection(false)
      connected = false
      acceptedLease = nil
      self.error = error.localizedDescription
      return
    }
    if ConnectionRecovery.retryable(error) {
      if connected {
        cancelPreviews()
        connected = false
        clearPhoneSharing()
        acceptedLease = nil
        nativeCommandReady = false
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
    if (phoneChat != nil || !nativeConfigured), let snapshotLease {
      await snapshots?.record(update, lease: snapshotLease)
    }
  }
  public func refreshList() async throws {
    if phoneChat == nil && !automaticConnectionEnabled && !connected {
      await loadPassiveNativeDisplay()
      return
    }
    if phoneChat == nil && nativeConfigured {
      if nativeReceiverBound { await loadNativeDisplay() }
      return
    }
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
    var visible =
      phoneChat == nil
      ? result.conversations.filter { !deletedIDs.contains($0.id) }
      : PhoneProductChat.visible(result, hiding: deletedIDs)
    visible += unlistedCreations.values
    // The feed lists only unarchived chats: one it lists is no longer archived, and the
    // archived rows read for the Archived list stay beside it.
    if archivedConversations.contains(where: { observed.contains($0.id) }) {
      archivedConversations.removeAll { observed.contains($0.id) }
    }
    visible += archivedConversations.filter { row in
      !deletedIDs.contains(row.id) && !visible.contains { $0.id == row.id }
    }
    if !unlistedCreations.isEmpty { visible.sort { $0.updatedAtMs > $1.updatedAtMs } }
    if conversations != visible { conversations = visible }
    if listComplete != result.complete { listComplete = result.complete }
    return NessaConversationList(conversations: visible, complete: result.complete)
  }
  public func refresh(_ id: String) async {
    if phoneChat == nil && !automaticConnectionEnabled && !connected {
      await loadPassiveNativeDisplay([id])
      return
    }
    if phoneChat == nil && nativeConfigured {
      guard nativeReceiverBound, !deletedIDs.contains(id), !pendingDeletionIDs.contains(id) else {
        return
      }
      await loadNativeDisplay([id])
      return
    }
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
  public func watchInbox() async {
    if phoneChat == nil && !automaticConnectionEnabled && !connected {
      await loadPassiveNativeDisplay()
      return
    }
    guard phoneChat == nil || connected else { return }
    await watch(nil)
  }
  public func watchConversation(_ id: String) async {
    if phoneChat == nil && !automaticConnectionEnabled && !connected {
      await loadPassiveNativeDisplay([id])
      return
    }
    guard phoneChat == nil || connected else { return }
    await watch(id)
  }
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
    if nativeConfigured && phoneChat == nil {
      if case .view(let cursor, let view) = update {
        viewCursors[view.conversationId] = cursor
      }
      if nativeReceiverBound { await loadNativeDisplay(id.map { [$0] } ?? []) }
      return
    }
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
    guard connected, conversationAuthorityReady, !busy, pendingLoadError == nil,
      pendingCreations.isEmpty
    else { return nil }
    let currentGeneration = generation
    let originalProfile = profile
    busy = true
    defer { if generation == currentGeneration { busy = false } }
    guard await validateNativeCommand(nil, generation: currentGeneration) else { return nil }
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
      if nativeConfigured && phoneChat == nil {
        // Creation belongs to the owner. Only an actual native transcript establishes phone access.
        unavailableNativeIDs.insert(id)
      } else {
        views[id] = NessaConversationView(
          conversationId: id, messages: [], permissions: [],
          truncated: false, interactionViewError: nil,
          runtime: agent.map { NessaRuntime(agent: $0) })
      }
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
  public func stopTurn(_ executionID: String, in conversationID: String) async {
    guard let phoneChat, let profile, connected, !accessRevoked else { return }
    await phoneChat.activate(cacheScope(profile))
    do {
      let outcome = try await phoneChat.stop(
        conversationID: conversationID, executionID: executionID)
      if case .failed(let code) = outcome, PhoneAccess.revoked(code) {
        accessRevoked = true
        setAutomaticConnection(false)
        error = "This phone’s access was revoked."
      }
    } catch {
      self.error = error.localizedDescription
    }
  }
  public func retryPhoneDelivery(_ commandID: String) async {
    guard let phoneChat, let profile, connected, !accessRevoked else { return }
    await phoneChat.activate(cacheScope(profile))
    do {
      let view = try await phoneChat.retry(commandID)
      phoneDeliveries = try await phoneChat.list()
      noteRevokedDeliveries([view])
    } catch {
      self.error = error.localizedDescription
    }
  }
  /// Where this profile's saved chats and sends live. A linked Mac is named
  /// by its pairing, so pairing again starts a fresh cache.
  private func cacheScope(_ profile: Profile) -> PhoneCacheScope {
    PhoneCacheScope(
      address: profile.address,
      credential: profile.linked.map { "linked-desktop:" + $0.uuidString.lowercased() }
        ?? profile.credential,
      instance: profile.instance)
  }

  private func noteRevokedDeliveries(_ current: [PhoneOutboxView]) {
    let revoked = current.contains { view in
      if case .failed(let code) = view.outcome { return PhoneAccess.revoked(code) }
      return false
    }
    if revoked {
      accessRevoked = true
      setAutomaticConnection(false)
      error = "This phone’s access was revoked."
    }
  }
  private func deliverThroughOutbox(
    _ text: String, attachments: [DraftAttachment], reply: MessageReply?, to id: String,
    identity: MessageCommandIdentity, generation currentGeneration: Int, profile currentProfile: Profile?,
    chat: PhoneProductChat
  ) async -> Bool {
    let contextual = reply?.contextualizing(text) ?? text
    if let currentProfile { await chat.activate(cacheScope(currentProfile)) }
    do {
      let view = try await chat.deliver(
        text: contextual, attachments: attachments, conversationID: id, identity: identity)
      let kept: Bool
      switch view.outcome {
      case .failed, .draft: kept = false
      case .accepted, .running, .done, .unknown: kept = true
      }
      guard generation == currentGeneration else { return kept }
      phoneDeliveries = (try? await chat.list()) ?? phoneDeliveries
      noteRevokedDeliveries([view])
      switch view.outcome {
      case .accepted, .running, .done, .unknown:
        if profile == currentProfile { recordAcknowledgment(identity.requestID) }
        if let reply, !deletedIDs.contains(id), !pendingDeletionIDs.contains(id) {
          replyProjections.removeValue(forKey: id)
          replyTargets[id + ":" + identity.executionID] = reply.id
          preferences.save(replyTargets, forKey: replyKey)
        }
        await refresh(id)
        return true
      case .failed(let code):
        error =
          PhoneAccess.revoked(code)
          ? "This phone’s access was revoked."
          : "The message was not sent."
        if PhoneAccess.revoked(code) {
          accessRevoked = true
          setAutomaticConnection(false)
        }
        return false
      case .draft:
        return false
      }
    } catch {
      if generation == currentGeneration { self.error = error.localizedDescription }
      return false
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
    guard await validateNativeCommand(id, generation: currentGeneration) else { return false }
    if let phoneChat {
      return await deliverThroughOutbox(
        text, attachments: attachments, reply: reply, to: id, identity: identity,
        generation: currentGeneration, profile: currentProfile, chat: phoneChat)
    }
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
    guard connected, !retry || conversationAuthorityReady, pendingLoadError == nil,
      !checkingCommands.contains(requestID)
    else {
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
        guard await validateNativeCommand(originalCommand.conversationID, generation: expected)
        else { return nil }
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
    guard connected, conversationAuthorityReady, !unavailableNativeIDs.contains(id) else { return }
    let currentGeneration = generation
    guard await validateNativeCommand(id, generation: currentGeneration) else { return }
    do {
      try await service.answer(permission, option: option, conversationID: id)
      guard generation == currentGeneration else { return }
      await refresh(id)
    } catch { if generation == currentGeneration { self.error = error.localizedDescription } }
  }
}
