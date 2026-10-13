import Foundation
import NessaFeatures

actor CoordinatorGate {
  private var entered = false
  private var released = false
  private var entering: [CheckedContinuation<Void, Never>] = []
  private var releasing: [CheckedContinuation<Void, Never>] = []
  func pause() async {
    entered = true
    for waiter in entering { waiter.resume() }
    entering.removeAll()
    if !released { await withCheckedContinuation { releasing.append($0) } }
  }
  func wait() async { if !entered { await withCheckedContinuation { entering.append($0) } } }
  func release() {
    released = true
    for waiter in releasing { waiter.resume() }
    releasing.removeAll()
  }
}

enum CoordinatorFixtureError: Error { case lostAnswer, save, close, withdrawal }
actor CoordinatorProfiles: PhoneProfileStoring {
  enum Fault { case creation, owner, receiver, nativeStatus }
  var value: PhoneProfiles?
  var fault: Fault?
  var writes = 0
  init(_ value: PhoneProfiles?) { self.value = value }
  func load() -> PhoneProfiles? { value }
  func configure(_ fault: Fault?) { self.fault = fault }
  func replaceExternally(_ value: PhoneProfiles) { self.value = value }
  func save(_ next: PhoneProfiles, replacing expected: PhoneProfiles?) throws {
    guard value == expected else { throw PhoneProfileStoreError.changed }
    try next.validate(replacing: expected)
    let record = next.profiles.first { $0.id == next.selected }!
    if (fault == .creation && record.creationAttempt != nil)
      || (fault == .owner && record.pairingStatus != nil)
      || (fault == .receiver && record.nativeReceiver != nil)
      || (fault == .nativeStatus && record.lastNativeStatus != nil)
    {
      throw CoordinatorFixtureError.save
    }
    writes += 1
    value = next
  }
}
actor CoordinatorCredentials: PhoneProfileCredentialStoring {
  var records: [String: String]
  init(_ profile: PhoneProfile) { records = [profile.credentialReference: "fixture"] }
  func load(reference: String) throws -> String {
    guard let value = records[reference] else { throw PhoneProfileCredentialError.missing }
    return value
  }
  func insertOrVerify(_ credential: String, reference: String) throws {
    if let existing = records[reference], existing != credential {
      throw PhoneProfileCredentialError.conflict
    }
    records[reference] = credential
  }
}
struct CoordinatorLocations: PhoneNativeLocationPreparing {
  func prepare(_ profile: PhoneProfile) -> RetainedSessionLocation {
    .init(root: "/fixture", directory: profile.nativeDirectory, address: profile.nativeAddress)
  }
}
actor CoordinatorGateway: AuthenticatedGatewaySessionProviding, GatewayPairingManaging {
  var source: AuthenticatedGatewaySession
  var status: GatewayPairingStatus
  var creates = 0
  var approvals = 0
  var lostCreate = false
  var createGate: CoordinatorGate?
  init(_ source: AuthenticatedGatewaySession, status: GatewayPairingStatus) {
    self.source = source
    self.status = status
  }
  func configure(lostCreate: Bool = false, gate: CoordinatorGate? = nil) {
    self.lostCreate = lostCreate
    createGate = gate
  }
  func changeSource(_ source: AuthenticatedGatewaySession) { self.source = source }
  func changeStatus(_ status: GatewayPairingStatus) { self.status = status }
  func authenticatedSession(for lease: GatewayConnectionLease) throws -> AuthenticatedGatewaySession
  {
    guard lease == source.connection else {
      throw PhoneProfileCoordinationRefusal.receiptSourceChanged
    }
    return source
  }
  func createDevice(on lease: GatewayConnectionLease) async throws -> GatewayPairingReceipt<
    GatewayPairingCreated
  > {
    creates += 1
    if let createGate { await createGate.pause() }
    if lostCreate { throw CoordinatorFixtureError.lostAnswer }
    return .init(source: source, value: .init(code: "ephemeral-fixture", status: status))
  }
  func pairingStatus(_ invitation: Data, on lease: GatewayConnectionLease) -> GatewayPairingReceipt<
    GatewayPairingStatus
  > {
    .init(source: source, value: status)
  }
  func approvePairing(_ invitation: Data, deviceKey: Data, on lease: GatewayConnectionLease)
    -> GatewayPairingReceipt<GatewayPairingApproval>
  {
    approvals += 1
    return .init(source: source, value: .init(status: status, activationStopped: .retryable))
  }
  func cancelPairing(_ invitation: Data, on lease: GatewayConnectionLease) -> GatewayPairingReceipt<
    GatewayPairingStatus
  > {
    .init(source: source, value: status)
  }
  func pendingPairings(on lease: GatewayConnectionLease) -> GatewayPairingReceipt<
    [GatewayPairingStatus]
  > {
    .init(source: source, value: [status])
  }
}
actor CoordinatorNative: RetainedSession {
  var local: RetainedLocalEnrollment?
  var observed: RetainedStatus
  var purge: RetainedPurge?
  var enrolls = 0
  var statuses = 0
  var refreshes = 0
  var compound: RetainedRefresh?
  var removeLocalOnRefresh = false
  var reads = 0
  var closes = 0
  var closed = false
  var closeGate: CoordinatorGate?
  var captureGate: CoordinatorGate?
  var failClose = false
  init(local: RetainedLocalEnrollment? = nil, status: RetainedStatus = coordinatorStatus()) {
    self.local = local
    observed = status
  }
  func configure(
    local: RetainedLocalEnrollment?, status: RetainedStatus, purge: RetainedPurge? = nil
  ) {
    self.local = local
    observed = status
    self.purge = purge
  }
  func hold(close: CoordinatorGate? = nil, capture: CoordinatorGate? = nil, failClose: Bool = false)
  {
    closeGate = close
    captureGate = capture
    self.failClose = failClose
  }
  func localEnrollment() async throws -> RetainedLocalEnrollment? {
    if let captureGate { await captureGate.pause() }
    guard !closed else { throw RetainedSessionError.closed }
    return local
  }
  func enroll(code: String) throws -> RetainedEnrollmentReceipt {
    enrolls += 1
    let receipt = coordinatorReceipt(phase: .claimed)
    local = coordinatorLocal(issued: false)
    observed = coordinatorStatus(receipt)
    return receipt
  }
  func retry(code: String) throws -> RetainedRetry { throw RetainedSessionError.invalidArgument }
  func status() throws -> RetainedStatus {
    statuses += 1
    guard !closed else { throw RetainedSessionError.closed }
    return observed
  }
  func setRefresh(_ value: RetainedRefresh, removeLocal: Bool = false) {
    compound = value
    removeLocalOnRefresh = removeLocal
  }
  func refresh() -> RetainedRefresh {
    refreshes += 1
    if removeLocalOnRefresh { local = nil }
    return compound ?? .init(initial: observed, read: nil, recheck: nil, selectionFailure: nil)
  }
  func cataloguePage(after: RetainedEntryKey?, maximum: UInt32) -> RetainedCataloguePage? {
    reads += 1
    return nil
  }
  func transcript(conversation: String, revision: UUID) throws -> RetainedTranscript {
    reads += 1
    throw RetainedSessionError.invalidArgument
  }
  func purgeReceipt(receiver: String) -> RetainedPurge? { purge }
  func close() async throws {
    closes += 1
    if let closeGate { await closeGate.pause() }
    if failClose { throw CoordinatorFixtureError.close }
    closed = true
  }
}
actor CoordinatorFactory: RetainedSessionFactory {
  let session: any RetainedSession
  let gate: CoordinatorGate?
  var opens = 0
  init(_ session: any RetainedSession, gate: CoordinatorGate? = nil) {
    self.session = session
    self.gate = gate
  }
  func open(_ location: RetainedSessionLocation) async -> any RetainedSession {
    opens += 1
    if let gate { await gate.pause() }
    return session
  }
}
actor CoordinatorWithdrawal: PhoneSnapshotWithdrawing {
  var scopes: [PhoneCacheScope] = []
  var fail = false
  func configure(fail: Bool) { self.fail = fail }
  func withdraw(_ scope: PhoneCacheScope) throws {
    scopes.append(scope)
    if fail { throw CoordinatorFixtureError.withdrawal }
  }
}
func coordinatorStatus(_ receipt: RetainedEnrollmentReceipt? = nil) -> RetainedStatus {
  .init(
    completionCaptured: true, failure: nil, purge: nil, purgeAttempted: false, purgeFailure: nil,
    receipt: receipt)
}
func coordinatorIntent() -> RetainedPublicIntent {
  .init(
    attempt: Data(repeating: 5, count: 16), consent: Data(repeating: 2, count: 16),
    consentClass: .deviceRead,
    consentClassName: "owner-published-class", expiryMs: 900, generation: 7,
    invitation: Data(repeating: 1, count: 16))
}
func coordinatorLocal(issued: Bool) -> RetainedLocalEnrollment {
  .init(
    publicIntent: coordinatorIntent(), deviceKey: Data(repeating: 3, count: 32),
    gatewayPin: Data(repeating: 4, count: 32),
    issued: issued ? .init(credential: "native-credential", receiver: "native-receiver") : nil)
}
func coordinatorReceipt(phase: RetainedEnrollmentPhase) -> RetainedEnrollmentReceipt {
  .init(
    accessEpoch: 99, attemptFailure: nil, attemptState: nil, audience: "owner",
    credential: phase == .claimed ? nil : "native-credential",
    organization: "owner", phase: phase, publicIntent: coordinatorIntent(),
    receiver: phase == .claimed ? nil : "native-receiver",
    resource: "owner", terminalCause: phase == .terminal ? .credentialRevoked : nil)
}
func coordinatorOwner(
  phase: GatewayPairingPhase = .available, className: String = "owner-published-class"
) -> GatewayPairingStatus {
  .init(
    invitationID: coordinatorIntent().invitation, consentID: coordinatorIntent().consent,
    generation: 7, consentClass: className,
    grant: .init(
      action: "conversation.read", resource: .init(organizationID: "owner", id: "owner")),
    createdAtMs: 100, expiresAtMs: 900,
    phase: phase,
    claimedDeviceKey: phase == .available ? nil : coordinatorLocal(issued: false).deviceKey,
    credentialID: nil, receiver: nil, terminal: nil, cleanupPending: false)
}
struct CoordinatorHarness {
  let profile: PhoneProfile
  let lease: GatewayConnectionLease
  let profiles: CoordinatorProfiles
  let credentials: CoordinatorCredentials
  let gateway: CoordinatorGateway
  let native: CoordinatorNative
  let factory: CoordinatorFactory
  let withdrawal: CoordinatorWithdrawal
  init(
    profile: PhoneProfile = exampleProfile(phase: .prepared), local: RetainedLocalEnrollment? = nil,
    status: RetainedStatus = coordinatorStatus(), openingGate: CoordinatorGate? = nil
  ) {
    self.profile = profile
    lease = .init()
    profiles = .init(exampleProfiles(profile))
    credentials = .init(profile)
    gateway = .init(
      .init(
        connection: lease,
        snapshot: .init(identity: profile.identity, expiresAt: nil, grants: [], methods: [])),
      status: coordinatorOwner())
    native = .init(local: local, status: status)
    factory = .init(native, gate: openingGate)
    withdrawal = .init()
  }
  func coordinator() -> PhoneProfileCoordinator {
    .init(
      profiles: profiles, credentials: credentials, locations: CoordinatorLocations(),
      identity: gateway,
      pairing: gateway, factory: factory, withdrawal: withdrawal)
  }
}
