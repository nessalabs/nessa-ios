import Foundation
import NessaFeatures
import Testing

private func vmSharingList(_ id: String) throws -> NessaConversationList {
  try JSONDecoder().decode(
    NessaConversationList.self,
    from: Data(
      "{\"conversations\":[{\"conversationId\":\"\(id)\",\"updatedAtMs\":1,\"running\":false}],\"complete\":true}"
        .utf8))
}
private func vmSharingView(_ id: String) throws -> NessaConversationView {
  try JSONDecoder().decode(
    NessaConversationView.self,
    from: Data(
      "{\"conversationId\":\"\(id)\",\"messages\":[],\"permissions\":[],\"truncated\":false}".utf8))
}
private func vmSharingSnapshot() throws -> PhoneProfileSnapshot {
  let owner = coordinatorOwner(phase: .active)
  let device = GatewayPairingStatus(
    invitationID: owner.invitationID, consentID: owner.consentID, generation: owner.generation,
    consentClass: owner.consentClass, grant: owner.grant, createdAtMs: owner.createdAtMs,
    expiresAtMs: owner.expiresAtMs, phase: .active, claimedDeviceKey: owner.claimedDeviceKey,
    credentialID: "native-credential", receiver: .init(id: "native-receiver", accessEpoch: 99),
    terminal: nil, cleanupPending: false)
  let profile = exampleProfile(phase: .prepared).recording(
    pairingStatus: device, nativeReceiver: "native-receiver", nativeStatus: nil,
    recoveredPurge: nil, retired: false)
  return try .init(
    registry: exampleProfiles(profile), local: coordinatorLocal(issued: true),
    nativeStatus: nil, source: nil)
}
private enum VMSharingFailure: Error { case lost, unavailable }

private actor VMSharingGateway: MessagingRepository, ConnectionLeasing,
  AuthenticatedGatewaySessionProviding, GatewayPairingManaging, GatewayConversationSharingProviding,
  CommandRecoveryProviding
{
  var identity: GatewaySessionSnapshot.Identity
  private var lease: GatewayConnectionLease?
  var mutations: [PhoneConversationShareIntent] = []
  var choicesGate: CoordinatorGate?
  var mutationGate: CoordinatorGate?
  var connectionGate: CoordinatorGate?
  var loseAnswer = false
  var sharedIDs: Set<String> = []
  var commandRecords: [PreparedConversationCommand] = []
  func seedCommand(_ command: PreparedConversationCommand) { commandRecords = [command] }
  func pendingCommands() -> [PreparedConversationCommand] { commandRecords }
  func create(_ intent: PreparedConversationCommand.Creation) -> String {
    creations += 1
    return "new-unshared"
  }
  func send(
    _ text: String, attachments: [DraftAttachment], conversationID: String,
    identity: MessageCommandIdentity, replyTo: String?
  ) -> String {
    sends += 1
    return identity.executionID
  }
  func checkCommand(_ requestID: String) -> ResolvedConversationCommand? {
    guard let index = commandRecords.firstIndex(where: { $0.requestID == requestID }) else {
      return nil
    }
    let command = commandRecords.remove(at: index)
    switch command {
    case .submit(let value):
      return .init(command: command, acknowledgment: .submitted(value.executionID))
    case .create(let value):
      return .init(command: command, acknowledgment: .created(value.conversationID))
    }
  }
  func retryCommand(_ requestID: String) throws -> ResolvedConversationCommand {
    guard let command = checkCommand(requestID) else { throw VMSharingFailure.unavailable }
    return command
  }
  var creations = 0
  func changeAccount() { identity = profileIdentity(Array(repeating: "other", count: 6)) }
  func holdChoices(_ gate: CoordinatorGate) { choicesGate = gate }
  func holdMutation(_ gate: CoordinatorGate) { mutationGate = gate }
  func holdConnection(_ gate: CoordinatorGate) { connectionGate = gate }
  func loseMutationAnswer() { loseAnswer = true }
  func allowMutationAnswer() { loseAnswer = false }
  func ownerConversationChoices(on lease: GatewayConnectionLease) async throws
    -> PhoneConversationShareReceipt<NessaConversationList>
  {
    let source = try authenticatedSession(for: lease)
    if let choicesGate { await choicesGate.pause() }
    return .init(source: source, value: try vmSharingList("owner-only"))
  }
  func conversationShares(_ id: String, on lease: GatewayConnectionLease) throws
    -> PhoneConversationShareReceipt<[PhoneConversationShare]>
  {
    .init(
      source: try authenticatedSession(for: lease),
      value: sharedIDs.contains(id)
        ? [
          .init(credentialId: "native-credential", capabilities: ["read"], policyRevision: 1, grantedAtMs: 1)
        ] : [])
  }
  func setConversationRead(_ intent: PhoneConversationShareIntent, on lease: GatewayConnectionLease)
    async throws -> PhoneConversationShareReceipt<PhoneConversationShareAcknowledgment>
  {
    let source = try authenticatedSession(for: lease)
    mutations.append(intent)
    if let mutationGate { await mutationGate.pause() }
    if loseAnswer { throw VMSharingFailure.lost }
    sharedIDs.insert(intent.conversationID)
    return .init(
      source: source,
      value: .init(requestId: intent.requestID.uuidString.lowercased(), applied: true))
  }
  var connections: [String] = []
  var lists = 0
  var reads = 0
  var sends = 0
  var readyLeases: [GatewayConnectionLease] = []
  var invitations: [GatewayPairingStatus] = [coordinatorOwner()]
  func setInvitations(_ values: [GatewayPairingStatus]) { invitations = values }
  var readGate: CoordinatorGate?
  var pendingGate: CoordinatorGate?
  var pendingRequests = 0
  func holdPending(_ gate: CoordinatorGate) { pendingGate = gate }
  func holdRead(_ gate: CoordinatorGate) { readGate = gate }
  init(identity: GatewaySessionSnapshot.Identity) { self.identity = identity }
  func connect(address: String, credential: String, instance: String) {
    connections.append(address)
  }
  func connectWithLease(address: String, credential: String, instance: String)
    async -> GatewayConnectionLease
  {
    connections.append(address)
    if let connectionGate { await connectionGate.pause() }
    let value = GatewayConnectionLease()
    lease = value
    return value
  }
  func retire(_ value: GatewayConnectionLease) { if lease == value { lease = nil } }
  func disconnect() { lease = nil }
  func authenticatedSession(for value: GatewayConnectionLease) throws -> AuthenticatedGatewaySession
  {
    guard value == lease else { throw NessaGatewayError.disconnected }
    readyLeases.append(value)
    return .init(
      connection: value,
      snapshot: .init(identity: identity, expiresAt: nil, grants: [], methods: []))
  }
  func pendingPairings(on value: GatewayConnectionLease) async throws -> GatewayPairingReceipt<
    [GatewayPairingStatus]
  > {
    let source = try authenticatedSession(for: value)
    let captured = invitations
    pendingRequests += 1
    if let pendingGate { await pendingGate.pause() }
    return .init(source: source, value: captured)
  }
  func createDevice(on lease: GatewayConnectionLease) throws -> GatewayPairingReceipt<
    GatewayPairingCreated
  > { throw NessaGatewayError.disconnected }
  func pairingStatus(_ invitation: Data, on lease: GatewayConnectionLease) throws
    -> GatewayPairingReceipt<GatewayPairingStatus>
  { throw NessaGatewayError.disconnected }
  func approvePairing(_ invitation: Data, deviceKey: Data, on lease: GatewayConnectionLease) throws
    -> GatewayPairingReceipt<GatewayPairingApproval>
  { throw NessaGatewayError.disconnected }
  func cancelPairing(_ invitation: Data, on lease: GatewayConnectionLease) throws
    -> GatewayPairingReceipt<GatewayPairingStatus>
  { throw NessaGatewayError.disconnected }
  func list() throws -> NessaConversationList {
    lists += 1
    return try vmSharingList("legacy-product")
  }
  func read(_ id: String) async throws -> NessaConversationView {
    reads += 1
    if let readGate { await readGate.pause() }
    return try vmSharingView(id)
  }
  func create(agent: String?, model: String?) -> String {
    creations += 1
    return "new-unshared"
  }
  func send(_ text: String, attachments: [DraftAttachment], conversationID: String) -> String {
    sends += 1
    return "turn"
  }
  func delete(_ conversationID: String) {}
  func listArchived() throws -> NessaConversationList {
    try JSONDecoder().decode(
      NessaConversationList.self, from: Data("{\"conversations\":[],\"complete\":true}".utf8))
  }
  func setArchived(_ archived: Bool, conversationID: String) {}
  func answer(_ permission: NessaPermission, option: NessaPermission.Option, conversationID: String)
  {}
}

private actor VMSharingSync: PhoneSyncRunning {
  let snapshot: PhoneProfileSnapshot
  var positiveDisplay = true
  var partialDisplay = false
  var emptyCatalogue = false
  var absentIDs: Set<String> = []
  var displayedTargets: [[String]] = []
  var product: VMSharingGateway?
  init(_ snapshot: PhoneProfileSnapshot) { self.snapshot = snapshot }
  func useProduct(_ value: VMSharingGateway) { product = value }
  func makePartial() { partialDisplay = true }
  func makeEmpty() { emptyCatalogue = true }
  func absent(_ id: String) { absentIDs.insert(id) }
  func readable(_ id: String) { absentIDs.remove(id) }
  func statusOnly() { positiveDisplay = false }
  func startup() -> PhoneSyncStartup? {
    .init(
      snapshot: snapshot,
      connection: .init(
        address: snapshot.profile.productAddress,
        credential: "fixture", instance: snapshot.profile.instance))
  }
  func savedProfiles() -> PhoneProfiles? { snapshot.registry }
  func restore() -> PhoneProfileSnapshot? { snapshot }
  func prepare(_ desired: PhoneProfile, credential: String, on lease: GatewayConnectionLease) throws
    -> PhoneProfileSnapshot
  { throw VMSharingFailure.unavailable }
  func startPairing(on lease: GatewayConnectionLease) throws -> PhoneProfileSnapshot {
    throw VMSharingFailure.unavailable
  }
  func observePairing(on lease: GatewayConnectionLease) async throws -> PhoneProfileSnapshot {
    let source = try await #require(product).authenticatedSession(for: lease)
    return try .init(
      registry: snapshot.registry, local: snapshot.local,
      nativeStatus: snapshot.nativeStatus, source: source)
  }
  func approve(_ confirmation: PhonePairingConfirmation, on lease: GatewayConnectionLease) throws
    -> PhoneProfileSnapshot
  { throw VMSharingFailure.unavailable }
  func resolveInvitation(_ invitation: Data, on lease: GatewayConnectionLease) throws
    -> PhoneProfileSnapshot
  { throw VMSharingFailure.unavailable }
  func cancelPairing(on lease: GatewayConnectionLease) throws -> PhoneProfileSnapshot {
    throw VMSharingFailure.unavailable
  }
  func discardUnenrolled() throws -> PhoneProfileSnapshot { throw VMSharingFailure.unavailable }
  func refresh(on lease: GatewayConnectionLease?) throws -> PhoneProfileSnapshot {
    throw VMSharingFailure.unavailable
  }
  func cataloguePage(after: RetainedEntryKey?, maximum: UInt32) throws -> PhoneScopedRetention<
    RetainedCataloguePage?
  > { throw VMSharingFailure.unavailable }
  func transcript(conversation: String, revision: UUID) throws -> PhoneScopedRetention<
    RetainedTranscript
  > { throw VMSharingFailure.unavailable }
  func display(on lease: GatewayConnectionLease?, conversations: [String], revision: UUID)
    async throws -> PhoneRetainedDisplay
  {
    displayedTargets.append(conversations)
    let saved = snapshot
    let status = coordinatorStatus(coordinatorReceipt(phase: .active))
    let refresh = RetainedRefresh(
      initial: status,
      read: positiveDisplay
        ? .init(
          complete: !partialDisplay, conversations: 1, failure: nil, moved: false, withdrawn: [])
        : nil,
      recheck: nil, selectionFailure: nil)
    let source = lease.map {
      AuthenticatedGatewaySession(
        connection: $0,
        snapshot: .init(identity: saved.profile.identity, expiresAt: nil, grants: [], methods: []))
    }
    let observed = try PhoneProfileSnapshot(
      registry: saved.registry, local: saved.local, nativeStatus: status, source: source,
      nativeRefresh: refresh)
    let scope = RetainedScope(
      accessEpoch: "99", incarnation: "one", origin: "owner", receiver: "native-receiver",
      schema: "1", stream: "catalogue")
    let page = RetainedCataloguePage(
      activeBoundary: nil, activeCursor: nil, completed: 1, entries: [], generation: 1, next: nil,
      scope: scope)
    var transcripts: [String: PhoneRetainedTranscriptRead] = [:]
    for id in conversations {
      if absentIDs.contains(id) {
        transcripts[id] = .failed(VMSharingFailure.unavailable)
        continue
      }
      let view = try vmSharingView(id)
      transcripts[id] = .available(
        .init(
          profileID: saved.profile.id, revision: saved.registry.revision,
          value: .init(
            state: .retained, scope: scope, downloaded: 1, applied: 1, facts: 1, generation: 1,
            view: .available(
              .init(
                json: Data(), revision: revision.uuidString, revisionEpoch: revision, display: view)
            ))))
    }
    return .init(
      snapshot: observed,
      catalogue: .init(
        profileID: saved.profile.id, revision: saved.registry.revision, pages: [page],
        list: try emptyCatalogue
          ? JSONDecoder().decode(
            NessaConversationList.self, from: Data("{\"conversations\":[],\"complete\":true}".utf8))
          : vmSharingList("native")), transcripts: transcripts, refreshFailure: nil)
  }
  func suspend() {}
  func close() {}
}

private actor VMSharingIntents: PhoneConversationShareIntentStoring {
  var records: [PhoneConversationShareRecord] = []
  var loadGate: CoordinatorGate?
  func holdLoad(_ gate: CoordinatorGate) { loadGate = gate }
  func load(profileID: UUID) async -> [PhoneConversationShareRecord] {
    let captured = records.filter { $0.intent.profileID == profileID }
    if let loadGate { await loadGate.pause() }
    return captured
  }
  func save(_ intent: PhoneConversationShareIntent) { records.append(.init(intent: intent)) }
  func acknowledge(
    _ intent: PhoneConversationShareIntent, value: PhoneConversationShareAcknowledgment
  ) {
    if let index = records.firstIndex(where: { $0.intent == intent }) {
      records[index] = .init(intent: intent, acknowledgment: value)
    }
  }
}
@MainActor private func vmSharingModel(
  _ sync: VMSharingSync, _ gateway: VMSharingGateway,
  _ store: VMSharingIntents
) -> MessagesViewModel {
  let service = MessagingService(repository: gateway)
  return .init(
    service: service, credentials: InMemoryCredentialStore(),
    preferences: InMemoryChatPreferences(),
    phoneSync: sync, conversationSharing: .init(product: service, sync: sync, store: store))
}
@MainActor private func vmSharingHarness() async throws
  -> (MessagesViewModel, VMSharingSync, VMSharingGateway, VMSharingIntents)
{
  let saved = try vmSharingSnapshot()
  let sync = VMSharingSync(saved)
  let gateway = VMSharingGateway(identity: saved.profile.identity)
  let store = VMSharingIntents()
  await sync.useProduct(gateway)
  let model = vmSharingModel(sync, gateway, store)
  await model.connect(address: "mock://product", credential: "fixture", instance: "phone")
  return (model, sync, gateway, store)
}

@Test @MainActor func sharingVMOwnerPickerCannotBecomeNativeHistoryOrGrantAutomatically()
  async throws
{
  let (model, sync, gateway, store) = try await vmSharingHarness()
  #expect(await gateway.mutations.isEmpty)
  #expect(await store.records.isEmpty)
  #expect(await model.performConversationSharing(.choices))
  #expect(model.phoneOwnerChoices?.conversations.map(\.id) == ["owner-only"])
  #expect(!model.conversations.contains { $0.id == "owner-only" })
  #expect(model.views["owner-only"] == nil)
  #expect(await gateway.mutations.isEmpty)
  #expect(await store.records.isEmpty)
  #expect(await sync.displayedTargets.allSatisfy(\.isEmpty))
  await model.suspendConnection()
}

@Test @MainActor func sharingVMStaleAuthenticatedAccountCannotDispatchOrPublishChoices()
  async throws
{
  let (model, _, gateway, store) = try await vmSharingHarness()
  await gateway.changeAccount()
  #expect(!(await model.performConversationSharing(.choices)))
  #expect(model.phoneOwnerChoices == nil && !model.nativeCommandReady)
  #expect(await gateway.mutations.isEmpty)
  #expect(await store.records.isEmpty)
  #expect(model.phoneSharingFailure is PhoneConversationSharingFailure)
  await model.suspendConnection()
}

@Test @MainActor func sharingVMLateOwnerChoicesDrainBeforeManualReplacement() async throws {
  let (model, _, gateway, _) = try await vmSharingHarness()
  let original = model.acceptedLease
  let draftScope = model.deliveryScopeRevision
  let feedRevision = model.connectionRevision
  let gate = CoordinatorGate()
  let replacementGate = CoordinatorGate()
  await gateway.holdChoices(gate)
  let choosing = Task { await model.performConversationSharing(.choices) }
  await gate.wait()
  #expect(model.deliveryScopeRevision == draftScope && model.connectionRevision == feedRevision)
  await gateway.holdConnection(replacementGate)
  let replacing = Task {
    await model.connect(address: "mock://replacement", credential: "other", instance: "other")
  }
  for _ in 0..<2000 {
    if model.currentGatewayAddress == "mock://replacement" { break }
    await Task.yield()
  }
  #expect(model.phoneOwnerChoices == nil && model.phoneSetupBusy)
  #expect(await gateway.connections == ["mock://product"])
  #expect(model.deliveryScopeRevision == draftScope + 1)
  let replacementFeedRevision = model.connectionRevision
  await gate.release()
  #expect(!(await choosing.value))
  await replacementGate.wait()
  // The obsolete sharing task must not restart the replacement account's feed.
  #expect(model.connectionRevision == replacementFeedRevision)
  #expect(model.deliveryScopeRevision == draftScope + 1 && model.phoneOwnerChoices == nil)
  await replacementGate.release()
  await replacing.value
  #expect(model.acceptedLease != original && model.phoneOwnerChoices == nil)
  #expect(await gateway.connections == ["mock://product", "mock://replacement"])
  await model.suspendConnection()
}

@Test @MainActor func sharingVMHeldPendingLoadCannotPublishToReplacement() async throws {
  let (model, _, gateway, store) = try await vmSharingHarness()
  await gateway.loseMutationAnswer()
  #expect(!(await model.performConversationSharing(.share("chosen"))))
  let original = try #require(model.pendingPhoneShares.first)
  let gate = CoordinatorGate()
  await store.holdLoad(gate)
  let choosing = Task { await model.performConversationSharing(.choices) }
  await gate.wait()
  // Suspend without reopening: no fresh pending load can hide a late stale publication.
  let background = Task { await model.suspendConnection() }
  for _ in 0..<2000 {
    if !model.connected && model.acceptedLease == nil { break }
    await Task.yield()
  }
  #expect(!model.connected && model.acceptedLease == nil && model.phoneSetupBusy)
  #expect(model.pendingPhoneShares.isEmpty && model.phoneOwnerChoices == nil)
  await gate.release()
  #expect(!(await choosing.value))
  await background.value
  // Assert after the held physical load has returned and its owner has settled.
  #expect(model.pendingPhoneShares.isEmpty && model.phoneOwnerChoices == nil)
  #expect(!model.phoneSetupBusy && !model.nativeCommandReady)
  #expect(await store.records.first?.intent == original)
  #expect(await gateway.connections == ["mock://product"])
}

@Test @MainActor func sharingVMCancelledObserverRetainsAdmissionAndOriginalRequestSettlement()
  async throws
{
  let (model, sync, gateway, store) = try await vmSharingHarness()
  let draftScope = model.deliveryScopeRevision
  let feedRevision = model.connectionRevision
  let originalLease = model.acceptedLease
  let gate = CoordinatorGate()
  await gateway.holdMutation(gate)
  let observer = Task { await model.performConversationSharing(.share("selected")) }
  await gate.wait()
  let admitted = try #require(await gateway.mutations.first)
  observer.cancel()
  #expect(model.deliveryScopeRevision == draftScope && model.connectionRevision == feedRevision)
  #expect(model.acceptedLease == originalLease)
  #expect(model.phoneSetupBusy && !model.canSubmit(in: "selected"))
  #expect(!(await model.performConversationSharing(.share("other"))))
  #expect(!(await model.performPhoneSetup(.observe)))
  await gate.release()
  #expect(await observer.value)
  #expect(model.deliveryScopeRevision == draftScope && model.connectionRevision == feedRevision + 1)
  #expect(model.acceptedLease == originalLease)
  #expect(await gateway.mutations == [admitted])
  #expect(await store.records.first?.intent == admitted)
  #expect(
    await store.records.first?.acknowledgment?.requestId
      == admitted.requestID.uuidString.lowercased())
  #expect(await sync.displayedTargets.last == ["selected"])
  #expect(model.views["selected"] != nil && model.canSubmit(in: "selected"))
  await model.suspendConnection()
}

@Test @MainActor func sharingVMAcknowledgedGrantCannotEnableSendWithoutPositiveNativeRead()
  async throws
{
  let (model, sync, gateway, _) = try await vmSharingHarness()
  await sync.statusOnly()
  #expect(await model.performConversationSharing(.share("selected")))
  #expect(await gateway.mutations.count == 1)
  #expect(!model.nativeCommandReady && !model.canSubmit(in: "selected"))
  #expect(!(await model.send("blocked", to: "selected")))
  #expect(await gateway.sends == 0)
  await model.suspendConnection()
}

@Test @MainActor func sharingVMPositivePartialNativeReadCanEnableExplicitEmptyConversation()
  async throws
{
  let (model, sync, _, _) = try await vmSharingHarness()
  await sync.makePartial()
  await sync.makeEmpty()
  #expect(await model.performConversationSharing(.share("selected-empty")))
  #expect(model.conversations.isEmpty)
  #expect(model.views["selected-empty"]?.messages.isEmpty == true)
  #expect(model.nativeCommandReady && model.canSubmit(in: "selected-empty"))
  #expect(await sync.displayedTargets.last == ["selected-empty"])
  await model.suspendConnection()
}

@Test @MainActor func sharingVMNewUnsharedConversationUsesExplicitGrantForExactCreatedIdentity()
  async throws
{
  let (model, sync, gateway, store) = try await vmSharingHarness()
  await sync.absent("new-unshared")
  let created = try #require(await model.create())
  #expect(created == "new-unshared")
  #expect(await gateway.creations == 1)
  #expect(await gateway.mutations.isEmpty)
  #expect(await store.records.isEmpty)
  #expect(model.needsPhoneSharing(in: created) && !model.canSubmit(in: created))
  #expect(model.views[created] == nil)
  #expect(model.submissionUnavailableReason(in: created) != nil)
  await model.refresh(created)
  #expect(model.needsPhoneSharing(in: created) && !model.canSubmit(in: created))
  #expect(!(await model.send("blocked", to: created)))
  #expect(await gateway.sends == 0)
  #expect(await gateway.mutations.isEmpty)
  await sync.readable(created)
  #expect(await model.performConversationSharing(.share(created)))
  #expect(await gateway.mutations.map(\.conversationID) == [created])
  #expect(await sync.displayedTargets.last == [created])
  #expect(model.canSubmit(in: created))
  #expect(model.submissionUnavailableReason(in: created) == nil)
  await model.suspendConnection()
}

@Test @MainActor func sharingVMLostReplyRequiresExplicitOriginalRetryAndRetainsExactRequest()
  async throws
{
  let (model, _, gateway, store) = try await vmSharingHarness()
  await gateway.loseMutationAnswer()
  #expect(!(await model.performConversationSharing(.share("selected"))))
  let original = try #require(model.pendingPhoneShares.first)
  #expect(await store.records.first?.intent == original)
  #expect(await gateway.mutations == [original])
  #expect(!model.canSubmit(in: "selected"))
  #expect(!(await model.performConversationSharing(.share("selected"))))
  #expect(await gateway.mutations == [original])
  await gateway.allowMutationAnswer()
  #expect(await model.performConversationSharing(.retry(original)))
  #expect(await gateway.mutations == [original, original])
  #expect(model.pendingPhoneShares.isEmpty && model.phoneSharingFailure == nil)
  #expect(
    await store.records.first?.acknowledgment?.requestId
      == original.requestID.uuidString.lowercased())
  #expect(model.canSubmit(in: "selected"))
  await model.suspendConnection()
}

@Test @MainActor func sharingVMSameAccountPreservesDraftScopeAndRestartsFeedOnlyAfterSettlement()
  async throws
{
  let (model, _, gateway, store) = try await vmSharingHarness()
  let draftScope = model.deliveryScopeRevision
  let feedRevision = model.connectionRevision
  let originalLease = model.acceptedLease
  let originalAddress = model.currentGatewayAddress
  let choiceGate = CoordinatorGate()
  let settlementGate = CoordinatorGate()
  await gateway.holdChoices(choiceGate)
  await store.holdLoad(settlementGate)
  let choosing = Task { await model.performConversationSharing(.choices) }
  await choiceGate.wait()
  #expect(model.phoneSetupBusy)
  #expect(model.deliveryScopeRevision == draftScope && model.connectionRevision == feedRevision)
  #expect(model.acceptedLease == originalLease && model.currentGatewayAddress == originalAddress)
  await choiceGate.release()
  await settlementGate.wait()
  // A source response and native refresh have arrived; the owned pending load is still physical.
  #expect(model.phoneOwnerChoices?.conversations.map(\.id) == ["owner-only"])
  #expect(model.phoneSetupBusy)
  #expect(model.deliveryScopeRevision == draftScope && model.connectionRevision == feedRevision)
  await settlementGate.release()
  #expect(await choosing.value)
  #expect(!model.phoneSetupBusy)
  #expect(model.deliveryScopeRevision == draftScope && model.connectionRevision == feedRevision + 1)
  #expect(model.acceptedLease == originalLease && model.currentGatewayAddress == originalAddress)
  #expect(await gateway.mutations.isEmpty)
  await model.suspendConnection()
}

@Test @MainActor func sharingVMKeepsPendingDraftRequestCorrelationUntilSameAccountReceipt()
  async throws
{
  let (model, _, gateway, _) = try await vmSharingHarness()
  let pending = PreparedConversationCommand.submit(
    .init(
      requestID: "00000000-0000-4000-8000-000000000011", conversationID: "native",
      executionID: "00000000-0000-4000-8000-000000000012", text: "Original draft"))
  await gateway.seedCommand(pending)
  await model.refreshPendingCommands()
  #expect(model.pendingCommands == [pending])
  let draftScope = model.deliveryScopeRevision
  let gate = CoordinatorGate()
  await gateway.holdChoices(gate)
  let choosing = Task { await model.performConversationSharing(.choices) }
  await gate.wait()
  // Publishing a fake-empty set here makes the thread discard the original draft owner.
  #expect(model.pendingCommands == [pending] && model.pendingLoadError == nil)
  #expect(model.deliveryScopeRevision == draftScope)
  await gate.release()
  #expect(await choosing.value)
  #expect(model.pendingCommands == [pending] && model.deliveryScopeRevision == draftScope)
  _ = await model.recoverCommand(pending.requestID, retry: false)
  #expect(model.pendingCommands.isEmpty)
  #expect(model.acknowledgedCommands.contains(pending.requestID))
  #expect(model.deliveryScopeRevision == draftScope)
  await model.suspendConnection()
}
