import Foundation
import NessaFeatures
import Testing

private enum VMDeletionFailure: Error { case write, lost, cache }
private let vmDeletionID = "00000000-0000-4000-8000-000000000001"
private let vmDeletionOtherID = "00000000-0000-4000-8000-000000000002"
private let vmDeletionAddress = "mock://deletion"
private func vmDeletionList(_ ids: [String]) throws -> NessaConversationList {
  let rows = ids.map { "{\"conversationId\":\"\($0)\",\"updatedAtMs\":1,\"running\":false}" }
    .joined(separator: ",")
  return try JSONDecoder().decode(
    NessaConversationList.self,
    from: Data("{\"conversations\":[\(rows)],\"complete\":true}".utf8))
}
private func vmDeletionView(_ id: String) throws -> NessaConversationView {
  try JSONDecoder().decode(
    NessaConversationView.self,
    from: Data(
      "{\"conversationId\":\"\(id)\",\"messages\":[],\"permissions\":[],\"truncated\":false,\"runtime\":{\"agent\":\"fixture-agent\"}}"
        .utf8))
}
private func vmDeletionSnapshot() throws -> PhoneProfileSnapshot {
  let profile = PhoneProfile(
    id: UUID(), phase: .prepared, productAddress: vmDeletionAddress,
    instance: "phone", nativeAddress: "127.0.0.1:9", identity: profileIdentity(),
    nativeReceiver: "native-receiver")
  return try .init(
    registry: exampleProfiles(profile), local: coordinatorLocal(issued: true),
    nativeStatus: nil, source: nil)
}

private actor VMDeletionStore: PhoneDeletionIntentStoring {
  var records: [PhoneDeletionRecord] = []
  var saveGate: CoordinatorGate?
  var loadGate: CoordinatorGate?
  var refusal: PhoneProfilePublication?
  var corrupt = false
  func holdSave(_ gate: CoordinatorGate) { saveGate = gate }
  func holdLoad(_ gate: CoordinatorGate) { loadGate = gate }
  func refuseSave(_ visibility: PhoneProfilePublication) { refusal = visibility }
  func damage() { corrupt = true }
  func loadForDisplay(cache: PhoneCacheScope, profileID: UUID?) async throws
    -> [PhoneDeletionRecord]
  {
    let captured = records.filter {
      $0.intent.scope.displaySelector == cache.key && $0.intent.scope.profileID == profileID
    }
    if let loadGate { await loadGate.pause() }
    if corrupt { throw PhoneDeletionStoreFailure.corrupt }
    return captured
  }
  func load(scope: PhoneDeletionScope) throws -> [PhoneDeletionRecord] {
    if corrupt { throw PhoneDeletionStoreFailure.corrupt }
    return records.filter { $0.intent.scope == scope }
  }
  func save(_ intent: PhoneDeletionIntent) async throws {
    if let saveGate { await saveGate.pause() }
    if refusal != .notPublished { records.append(.init(intent: intent)) }
    if let refusal {
      throw PhoneDeletionStoreFailure.write(
        refusal, underlying: VMDeletionFailure.write,
        reconciliation: VMDeletionFailure.cache)
    }
  }
  func acknowledge(_ intent: PhoneDeletionIntent, value: PhoneDeletionAcknowledgment) throws {
    guard let index = records.firstIndex(where: { $0.intent == intent }) else {
      throw PhoneDeletionStoreFailure.changed
    }
    records[index] = .init(intent: intent, acknowledgment: value)
  }
}

private actor VMDeletionGateway: MessagingRepository, ConnectionLeasing, GatewayConversationDeleting
{
  var connections: [String] = []
  var deletions: [PhoneDeletionIntent] = []
  var observations: [String] = []
  var sends = 0
  var legacyDeletes = 0
  var offline = false
  var lost = false
  var applied = false
  var mutationGate: CoordinatorGate?
  var connectionGate: CoordinatorGate?
  var rows = [vmDeletionID, vmDeletionOtherID]
  var observation: PhoneDeletionObservation = .readable
  private var lease: GatewayConnectionLease?
  private var identity = profileIdentity()
  func setOffline() { offline = true }
  func holdMutation(_ gate: CoordinatorGate) { mutationGate = gate }
  func holdConnection(_ gate: CoordinatorGate) { connectionGate = gate }
  func loseReply() { lost = true }
  func allowReply() { lost = false }
  func omit(_ id: String) { rows.removeAll { $0 == id } }
  func observeAs(_ value: PhoneDeletionObservation) { observation = value }
  func connect(address: String, credential: String, instance: String) async throws {
    _ = try await connectWithLease(address: address, credential: credential, instance: instance)
  }
  func connectWithLease(address: String, credential: String, instance: String) async throws
    -> GatewayConnectionLease
  {
    connections.append(address)
    if let connectionGate { await connectionGate.pause() }
    if offline { throw URLError(.cannotConnectToHost) }
    if address != vmDeletionAddress {
      identity = profileIdentity(Array(repeating: "other", count: 6))
    }
    let next = GatewayConnectionLease()
    lease = next
    return next
  }
  func authenticatedSession(for selected: GatewayConnectionLease) throws
    -> AuthenticatedGatewaySession
  {
    guard selected == lease else { throw NessaGatewayError.disconnected }
    return .init(
      connection: selected,
      snapshot: .init(identity: identity, expiresAt: nil, grants: [], methods: []))
  }
  func retire(_ selected: GatewayConnectionLease) { if lease == selected { lease = nil } }
  func disconnect() { lease = nil }
  func deleteConversation(_ intent: PhoneDeletionIntent, on selected: GatewayConnectionLease)
    async throws -> PhoneDeletionReceipt<PhoneDeletionAcknowledgment>
  {
    let source = try authenticatedSession(for: selected)
    deletions.append(intent)
    if let mutationGate { await mutationGate.pause() }
    if lost { throw VMDeletionFailure.lost }
    return .init(
      source: source,
      value: .init(requestId: intent.requestID.uuidString.lowercased(), applied: applied))
  }
  func observeDeletion(_ id: String, on selected: GatewayConnectionLease) throws
    -> PhoneDeletionReceipt<PhoneDeletionObservation>
  {
    observations.append(id)
    return .init(source: try authenticatedSession(for: selected), value: observation)
  }
  func list() throws -> NessaConversationList { try vmDeletionList(rows) }
  func read(_ id: String) throws -> NessaConversationView { try vmDeletionView(id) }
  func create(agent: String?, model: String?) -> String { vmDeletionOtherID }
  func send(_ text: String, attachments: [DraftAttachment], conversationID: String) -> String {
    sends += 1
    return "turn"
  }
  func delete(_ conversationID: String) { legacyDeletes += 1 }
  func answer(_ permission: NessaPermission, option: NessaPermission.Option, conversationID: String)
  {}
}

private actor VMDeletionSnapshots: PhoneSnapshotStoring {
  var value: PhoneSnapshot
  var saves = 0
  init() throws {
    var value = PhoneSnapshot()
    value.list = try vmDeletionList([vmDeletionID, vmDeletionOtherID])
    value.views[vmDeletionID] = try vmDeletionView(vmDeletionID)
    value.recentViews = [vmDeletionID]
    self.value = value
  }
  func load(_ scope: PhoneCacheScope) -> PhoneSnapshot? { value }
  func save(_ value: PhoneSnapshot, scope: PhoneCacheScope) {
    saves += 1
    self.value = value
  }
}

private actor VMDeletionSync: PhoneSyncRunning {
  let snapshot: PhoneProfileSnapshot
  var positive = true
  var absent: Set<String> = []
  var tombstones: Set<String> = []
  var transcriptTombstones: Set<String> = []
  var withdrawals: [String] = []
  var requests: [[String]] = []
  init(_ snapshot: PhoneProfileSnapshot) { self.snapshot = snapshot }
  func statusOnly() { positive = false }
  func omit(_ id: String) { absent.insert(id) }
  func tombstone(_ id: String) { tombstones.insert(id) }
  func deletedTranscriptOnly(_ id: String) { transcriptTombstones.insert(id) }
  func withdraw(_ id: String) { withdrawals.append(id) }
  func startup() -> PhoneSyncStartup? {
    .init(
      snapshot: snapshot,
      connection: .init(address: vmDeletionAddress, credential: "fixture", instance: "phone"))
  }
  func savedProfiles() -> PhoneProfiles? { snapshot.registry }
  func restore() -> PhoneProfileSnapshot? { snapshot }
  func prepare(_ desired: PhoneProfile, credential: String, on lease: GatewayConnectionLease) throws
    -> PhoneProfileSnapshot
  { throw VMDeletionFailure.cache }
  func startPairing(on lease: GatewayConnectionLease) throws -> PhoneProfileSnapshot {
    throw VMDeletionFailure.cache
  }
  func observePairing(on lease: GatewayConnectionLease) -> PhoneProfileSnapshot { snapshot }
  func approve(_ confirmation: PhonePairingConfirmation, on lease: GatewayConnectionLease) throws
    -> PhoneProfileSnapshot
  { throw VMDeletionFailure.cache }
  func resolveInvitation(_ invitation: Data, on lease: GatewayConnectionLease) throws
    -> PhoneProfileSnapshot
  { throw VMDeletionFailure.cache }
  func cancelPairing(on lease: GatewayConnectionLease) throws -> PhoneProfileSnapshot {
    throw VMDeletionFailure.cache
  }
  func discardUnenrolled() throws -> PhoneProfileSnapshot { throw VMDeletionFailure.cache }
  func refresh(on lease: GatewayConnectionLease?) throws -> PhoneProfileSnapshot {
    throw VMDeletionFailure.cache
  }
  func cataloguePage(after: RetainedEntryKey?, maximum: UInt32) throws -> PhoneScopedRetention<
    RetainedCataloguePage?
  > { throw VMDeletionFailure.cache }
  func transcript(conversation: String, revision: UUID) throws -> PhoneScopedRetention<
    RetainedTranscript
  > { throw VMDeletionFailure.cache }
  func display(on lease: GatewayConnectionLease?, conversations: [String], revision: UUID) throws
    -> PhoneRetainedDisplay
  {
    requests.append(conversations)
    let status = coordinatorStatus(coordinatorReceipt(phase: .active))
    let refresh = RetainedRefresh(
      initial: status,
      read: positive
        ? .init(
          complete: false, conversations: 2, failure: nil, moved: false, withdrawn: withdrawals)
        : nil,
      recheck: nil, selectionFailure: nil)
    let source = lease.map {
      AuthenticatedGatewaySession(
        connection: $0,
        snapshot: .init(
          identity: snapshot.profile.identity, expiresAt: nil, grants: [], methods: []))
    }
    let observed = try PhoneProfileSnapshot(
      registry: snapshot.registry, local: snapshot.local,
      nativeStatus: status, source: source, nativeRefresh: refresh)
    let scope = RetainedScope(
      accessEpoch: "99", incarnation: "one", origin: "owner", receiver: "native-receiver",
      schema: "1", stream: "catalogue")
    let entries = tombstones.map {
      RetainedCatalogueEntry(
        agent: nil, archived: nil, createdAtMs: nil,
        deleted: true, key: .init(creation: 1, id: $0), model: nil, preview: nil, revision: 2,
        title: nil, updatedAtMs: nil)
    }
    let page = RetainedCataloguePage(
      activeBoundary: nil, activeCursor: nil, completed: 2,
      entries: entries, generation: 2, next: nil, scope: scope)
    var transcripts: [String: PhoneRetainedTranscriptRead] = [:]
    for id in conversations {
      let state: RetainedTranscriptState =
        (tombstones.contains(id) || transcriptTombstones.contains(id))
        ? .deleted : absent.contains(id) ? .notLoaded : .retained
      let view: RetainedViewOutcome =
        state == .retained
        ? .available(
          .init(
            json: Data(), revision: revision.uuidString, revisionEpoch: revision,
            display: try vmDeletionView(id))) : .absent
      let transcriptScope = RetainedScope(
        accessEpoch: scope.accessEpoch,
        incarnation: scope.incarnation, origin: scope.origin, receiver: scope.receiver,
        schema: scope.schema, stream: id)
      transcripts[id] = .available(
        .init(
          profileID: snapshot.profile.id, revision: snapshot.registry.revision,
          value: .init(
            state: state, scope: state == .retained ? transcriptScope : nil,
            downloaded: state == .retained ? 1 : nil, applied: state == .retained ? 1 : nil,
            facts: state == .retained ? 1 : nil, generation: state == .retained ? 2 : nil,
            view: view)))
    }
    return .init(
      snapshot: observed,
      catalogue: .init(
        profileID: snapshot.profile.id,
        revision: snapshot.registry.revision, pages: [page],
        list: try vmDeletionList(
          [vmDeletionID, vmDeletionOtherID].filter {
            !absent.contains($0) && !tombstones.contains($0) && !withdrawals.contains($0)
          })),
      transcripts: transcripts, refreshFailure: nil)
  }
  func suspend() {}
  func close() {}
}
