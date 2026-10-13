import Foundation
import NessaFeatures
import Testing

private enum ApprovalFault: Error, Equatable { case publication, source, native, stale }
private func approvalContext(principal: String = "owner") -> PhoneOwnerApprovalContext {
  let identity = GatewaySessionSnapshot.Identity(
    gatewayID: "gateway", principalID: principal, organizationID: "organization",
    membershipID: "membership", credentialID: "bootstrap-id", audienceID: "gateway")
  let resource = GatewaySessionSnapshot.Resource(organizationID: "organization", id: "gateway")
  return .init(
    bootstrap: identity, productAddress: "wss://gateway.example/session", instance: "phone",
    nativeAddress: "127.0.0.1:19744", gatewayPin: Data(repeating: 4, count: 44),
    consentClass: "gateway-owner-conversation-read-write",
    grants: ["conversation.read", "conversation.write", "server.read"].map {
      .init(action: $0, resource: resource)
    })
}
private actor ApprovalSource: AuthenticatedGatewaySessionProviding {
  var value: AuthenticatedGatewaySession
  var reads = 0
  init(_ context: PhoneOwnerApprovalContext, lease: GatewayConnectionLease) {
    value = .init(
      connection: lease,
      snapshot: .init(
        identity: context.bootstrap, expiresAt: nil, grants: context.grants, methods: []))
  }
  func replace(_ context: PhoneOwnerApprovalContext, lease: GatewayConnectionLease) {
    value = .init(
      connection: lease,
      snapshot: .init(
        identity: context.bootstrap, expiresAt: nil, grants: context.grants, methods: []))
  }
  func authenticatedSession(for lease: GatewayConnectionLease) throws -> AuthenticatedGatewaySession
  {
    reads += 1
    guard value.connection == lease else { throw ApprovalFault.source }
    return value
  }
}
private actor ApprovalStore: PhoneOwnerApprovalStoring {
  var rows: [PhoneOwnerApprovalRecord] = []
  var publications = 0
  var failing: Int?
  var visibleFailure = false
  var gates: [Int: CoordinatorGate] = [:]
  func configure(
    failure: Int? = nil, visible: Bool = false, gate: CoordinatorGate? = nil, write: Int = 1
  ) {
    failing = failure
    visibleFailure = visible
    if let gate { gates[write] = gate }
  }
  func replace(_ rows: [PhoneOwnerApprovalRecord]) { self.rows = rows }
  func load() -> [PhoneOwnerApprovalRecord] { rows }
  func publish(_ next: [PhoneOwnerApprovalRecord], replacing expected: [PhoneOwnerApprovalRecord])
    async throws
  {
    guard rows == expected else { throw PhoneOwnerApprovalRefusal.changed }
    publications += 1
    let number = publications
    if let gate = gates[number] { await gate.pause() }
    guard rows == expected else { throw PhoneOwnerApprovalRefusal.changed }
    if failing == number {
      if visibleFailure { rows = next }
      throw ApprovalFault.publication
    }
    rows = next
  }
}
private actor ApprovalPrivateState {
  var proofs: [UUID: PhoneOwnerApprovalPreparation] = [:]
  func prepare(_ reservation: PhoneOwnerApprovalReservation) throws -> PhoneOwnerApprovalPreparation
  {
    if let value = proofs[reservation.profileID] {
      guard value.reservation == reservation else { throw ApprovalFault.native }
      return value
    }
    let value = PhoneOwnerApprovalPreparation(
      reservation: reservation,
      deviceKey: Data(repeating: 5, count: 32), signature: Data(repeating: 6, count: 64),
      digest: Data(repeating: 7, count: 32))
    proofs[reservation.profileID] = value
    return value
  }
}
private actor ApprovalNative: PhoneOwnerApprovalPreparing {
  let state: ApprovalPrivateState
  var preparations = 0
  var closes = 0
  var gate: CoordinatorGate?
  var closingGate: CoordinatorGate?
  var returned: PhoneOwnerApprovalPreparation?
  var replacement: PhoneOwnerApprovalPreparation?
  var failClose = false
  init(_ state: ApprovalPrivateState = ApprovalPrivateState()) { self.state = state }
  func hold(_ gate: CoordinatorGate) { self.gate = gate }
  func configure(
    close: CoordinatorGate? = nil, replacement: PhoneOwnerApprovalPreparation? = nil,
    failure: Bool = false
  ) {
    closingGate = close
    self.replacement = replacement
    failClose = failure
  }
  func prepare(_ reservation: PhoneOwnerApprovalReservation) async throws
    -> PhoneOwnerApprovalPreparation
  {
    preparations += 1
    let value = try await state.prepare(reservation)
    returned = value
    if let gate { await gate.pause() }
    return replacement ?? value
  }
  func close() async throws {
    closes += 1
    if let closingGate { await closingGate.pause() }
    if failClose { throw ApprovalFault.native }
  }
}
private actor ApprovalCurrent {
  var retired = false
  func retire() { retired = true }
  func check() throws { if retired { throw ApprovalFault.stale } }
}
private actor ApprovalCompletion {
  var finished = false
  func finish() { finished = true }
}
private struct ApprovalHarness {
  let context: PhoneOwnerApprovalContext
  let lease: GatewayConnectionLease
  let store: ApprovalStore
  let native: ApprovalNative
  let source: ApprovalSource
  let current = ApprovalCurrent()
  let journal: PhoneOwnerApprovalJournal
  init(maximum: Int = 64, context: PhoneOwnerApprovalContext = approvalContext()) {
    self.context = context
    lease = .init()
    store = .init()
    native = .init()
    source = .init(context, lease: lease)
    journal = .init(store: store, native: native, source: source, maximumRecords: maximum)
  }
  func reserve() async throws -> PhoneOwnerApprovalReservation {
    try await journal.reserve(context, on: lease, current: { try await current.check() })
  }
  func prepare(_ original: PhoneOwnerApprovalReservation) async throws
    -> PhoneOwnerApprovalPreparation
  {
    try await journal.prepare(original, on: lease, current: { try await current.check() })
  }
}

@Test func approvalReservationPublicationPrecedesAnyNativePreparation() async throws {
  let h = ApprovalHarness()
  let gate = CoordinatorGate()
  await h.store.configure(gate: gate)
  let reserving = Task { try await h.reserve() }
  await gate.wait()
  #expect(await h.native.preparations == 0)
  #expect(await h.store.rows.isEmpty)
  await #expect(throws: PhoneOwnerApprovalRefusal.busy) { _ = try await h.reserve() }
  await gate.release()
  let original = try await reserving.value
  #expect(await h.store.rows.map(\.reservation) == [original])
  #expect(original.context == h.context)
  try await h.journal.close()
}

@Test func approvalFailedReservationRetainsOriginalAndHasZeroNativeEffects() async throws {
  let h = ApprovalHarness()
  await h.store.configure(failure: 1)
  do {
    _ = try await h.reserve()
    Issue.record("Failed durable reserve escaped")
  } catch let failure as PhoneOwnerApprovalFailure {
    #expect(failure.reservation != nil && failure.preparation == nil)
    #expect(failure.underlying as? ApprovalFault == .publication)
  }
  #expect(await h.native.preparations == 0)
  #expect(await h.store.rows.isEmpty)
  try await h.journal.close()
}

@Test func approvalCancelledObserverKeepsPhysicalAdmissionAndOriginalPreparation() async throws {
  let h = ApprovalHarness()
  let original = try await h.reserve()
  let gate = CoordinatorGate()
  await h.native.hold(gate)
  let preparing = Task { try await h.prepare(original) }
  await gate.wait()
  preparing.cancel()
  await #expect(throws: PhoneOwnerApprovalRefusal.busy) { _ = try await h.reserve() }
  #expect(await h.native.preparations == 1)
  await gate.release()
  let proof = try await preparing.value
  #expect(proof.reservation == original)
  #expect(try await h.journal.records().first?.preparation == proof)
  try await h.journal.close()
}

@Test func approvalCloseJoinsFactualPublicationAfterNativeAndObserverCancellation() async throws {
  let h = ApprovalHarness()
  let original = try await h.reserve()
  let preparingGate = CoordinatorGate()
  let closeGate = CoordinatorGate()
  let publicationGate = CoordinatorGate()
  await h.native.hold(preparingGate)
  await h.native.configure(close: closeGate)
  await h.store.configure(gate: publicationGate, write: 3)
  let preparing = Task { try await h.prepare(original) }
  await preparingGate.wait()
  let completion = ApprovalCompletion()
  let close = Task {
    try await h.journal.close()
    await completion.finish()
  }
  await closeGate.wait()
  close.cancel()
  let repeated = Task { try await h.journal.close() }
  await closeGate.release()
  await preparingGate.release()
  await publicationGate.wait()
  #expect(await completion.finished == false)
  #expect(await h.native.closes == 1)
  await #expect(throws: PhoneOwnerApprovalRefusal.closed) { _ = try await h.reserve() }
  await publicationGate.release()
  do {
    _ = try await preparing.value
    Issue.record("Closed preparation was published")
  } catch let failure as PhoneOwnerApprovalFailure {
    #expect(failure.underlying as? PhoneOwnerApprovalRefusal == .closed)
    #expect(failure.reservation == original && failure.preparation != nil)
  }
  try await close.value
  try await repeated.value
  #expect(await completion.finished)
  #expect(await h.store.rows.first?.preparation?.reservation == original)
}

@Test func approvalRetiredCurrentStillStoresExactAcceptedNativeFacts() async throws {
  let h = ApprovalHarness()
  let original = try await h.reserve()
  let gate = CoordinatorGate()
  await h.native.hold(gate)
  let preparing = Task { try await h.prepare(original) }
  await gate.wait()
  await h.current.retire()
  await gate.release()
  do {
    _ = try await preparing.value
    Issue.record("Stale observer received preparation")
  } catch let failure as PhoneOwnerApprovalFailure {
    #expect(failure.underlying as? ApprovalFault == .stale)
    #expect(failure.reservation == original)
    #expect(failure.preparation == (await h.store.rows.first?.preparation))
  }
  #expect(await h.store.rows.first?.preparation != nil)
  try await h.journal.close()
}

@Test func approvalChangedSourceCannotBorrowOriginalBootstrapIdentity() async throws {
  let h = ApprovalHarness()
  let original = try await h.reserve()
  let gate = CoordinatorGate()
  await h.native.hold(gate)
  let preparing = Task { try await h.prepare(original) }
  await gate.wait()
  await h.source.replace(approvalContext(principal: "foreign-owner"), lease: h.lease)
  await gate.release()
  do {
    _ = try await preparing.value
    Issue.record("Foreign source received original proof")
  } catch let failure as PhoneOwnerApprovalFailure {
    #expect(failure.underlying as? PhoneOwnerApprovalRefusal == .changed)
    #expect(failure.source?.snapshot.identity == original.context.bootstrap)
  }
  #expect(await h.store.rows.first?.preparation != nil)
  try await h.journal.close()
}

@Test func approvalVisibleFailedPreparationIsNotDurableAndRestoresSameOriginalPrivateKey()
  async throws
{
  let h = ApprovalHarness()
  let original = try await h.reserve()
  await h.store.configure(failure: 3, visible: true)
  do {
    _ = try await h.prepare(original)
    Issue.record("Visible failed write treated as durable")
  } catch let failure as PhoneOwnerApprovalFailure {
    #expect(failure.underlying as? ApprovalFault == .publication)
    #expect(failure.preparation != nil)
  }
  let visible = try #require(await h.store.rows.first?.preparation)
  try await h.journal.close()
  let native = ApprovalNative(h.native.state)
  let reopened = PhoneOwnerApprovalJournal(store: h.store, native: native, source: h.source)
  await h.store.configure(failure: 4)
  do {
    _ = try await reopened.prepare(original, on: h.lease, current: {})
    Issue.record("Recovery used visible bytes without successful republication")
  } catch let failure as PhoneOwnerApprovalFailure {
    #expect(failure.underlying as? ApprovalFault == .publication)
  }
  #expect(await native.preparations == 0)
  await h.store.configure()
  let restored = try await reopened.prepare(original, on: h.lease, current: {})
  #expect(restored == visible)
  #expect(await native.preparations == 1)
  #expect(await h.native.state.proofs.count == 1)
  try await reopened.close()
}

@Test func approvalExistingPreparedRecordStillChecksNativePrivateScope() async throws {
  let h = ApprovalHarness()
  let original = try await h.reserve()
  let first = try await h.prepare(original)
  let changed = PhoneOwnerApprovalPreparation(
    reservation: original,
    deviceKey: Data(repeating: 9, count: 32), signature: first.signature, digest: first.digest)
  await h.native.configure(replacement: changed)
  do {
    _ = try await h.prepare(original)
    Issue.record("Replacement private key accepted")
  } catch let failure as PhoneOwnerApprovalFailure {
    #expect(failure.underlying as? PhoneOwnerApprovalRefusal == .changed)
    #expect(failure.preparation == changed)
  }
  #expect(await h.native.preparations == 2)
  #expect(await h.store.rows.first?.preparation == first)
  try await h.journal.close()
}

@Test func approvalNativeWrongReservationCannotBeStoredUnderOriginal() async throws {
  let h = ApprovalHarness()
  let original = try await h.reserve()
  let foreign = PhoneOwnerApprovalReservation(
    profileID: UUID(), requestID: original.requestID, context: original.context)
  let value = PhoneOwnerApprovalPreparation(
    reservation: foreign,
    deviceKey: Data(repeating: 1, count: 32), signature: Data(repeating: 2, count: 64),
    digest: Data(repeating: 3, count: 32))
  await h.native.configure(replacement: value)
  do {
    _ = try await h.prepare(original)
    Issue.record("Wrong native scope accepted")
  } catch let failure as PhoneOwnerApprovalFailure {
    #expect(failure.underlying as? PhoneOwnerApprovalRefusal == .changed)
    #expect(failure.reservation == original && failure.preparation == value)
  }
  #expect(await h.store.rows.first?.preparation == nil)
  try await h.journal.close()
}

@Test func approvalPendingOriginalCannotRetargetDiscoveryOrGrantOrder() async throws {
  let h = ApprovalHarness()
  let original = try await h.reserve()
  for changed in [
    PhoneOwnerApprovalContext(
      bootstrap: h.context.bootstrap, productAddress: h.context.productAddress,
      instance: h.context.instance, nativeAddress: "127.0.0.1:29999",
      gatewayPin: h.context.gatewayPin,
      consentClass: h.context.consentClass, grants: h.context.grants),
    PhoneOwnerApprovalContext(
      bootstrap: h.context.bootstrap, productAddress: h.context.productAddress,
      instance: h.context.instance, nativeAddress: h.context.nativeAddress,
      gatewayPin: h.context.gatewayPin,
      consentClass: h.context.consentClass, grants: h.context.grants.reversed()),
  ] {
    do {
      _ = try await h.journal.reserve(changed, on: h.lease, current: {})
      Issue.record("Original retargeted")
    } catch let failure as PhoneOwnerApprovalFailure {
      #expect(failure.underlying as? PhoneOwnerApprovalRefusal == .unresolved)
      #expect(failure.reservation == original)
    }
  }
  #expect(await h.store.rows.map(\.reservation) == [original])
  #expect(await h.native.preparations == 0)
  try await h.journal.close()
}

@Test func approvalQuotaAndCorruptionDoNotEvictOrPrepare() async throws {
  let h = ApprovalHarness(maximum: 1)
  let original = try await h.reserve()
  let foreign = approvalContext(principal: "other")
  await h.source.replace(foreign, lease: h.lease)
  do {
    _ = try await h.journal.reserve(foreign, on: h.lease, current: {})
    Issue.record("Quota evicted original")
  } catch let failure as PhoneOwnerApprovalFailure {
    #expect(failure.underlying as? PhoneOwnerApprovalRefusal == .capacity)
  }
  #expect(await h.store.rows.map(\.reservation) == [original])
  await h.store.replace([.init(reservation: original, schema: 2)])
  await #expect(throws: PhoneOwnerApprovalRefusal.invalid) { _ = try await h.journal.records() }
  #expect(await h.native.preparations == 0)
  try await h.journal.close()
}

@Test func approvalCanonicalCompleteConsentAndByteExactNamespaceRoundTrip() async throws {
  let h = ApprovalHarness(context: approvalContext(principal: "é"))
  let original = try await h.reserve()
  let proof = try await h.prepare(original)
  let records = try await h.journal.records()
  let bytes = try JSONEncoder().encode(records)
  #expect(try JSONDecoder().decode([PhoneOwnerApprovalRecord].self, from: bytes) == records)
  let decomposed = approvalContext(principal: "e\u{301}")
  #expect(original.context != decomposed)
  do {
    _ = try await h.journal.reserve(decomposed, on: h.lease, current: {})
    Issue.record("Normalized bootstrap namespace")
  } catch let failure as PhoneOwnerApprovalFailure {
    #expect(failure.underlying as? PhoneOwnerApprovalRefusal == .changed)
  }
  let partial = PhoneOwnerApprovalContext(
    bootstrap: h.context.bootstrap,
    productAddress: h.context.productAddress, instance: h.context.instance,
    nativeAddress: h.context.nativeAddress, gatewayPin: h.context.gatewayPin,
    consentClass: h.context.consentClass, grants: Array(h.context.grants.prefix(2)))
  #expect(throws: PhoneOwnerApprovalRefusal.invalid) { try partial.validate() }
  #expect(proof.reservation == original)
  try await h.journal.close()
}

@Test func approvalReservationRepublicationPrecedesNativeSideEffects() async throws {
  let h = ApprovalHarness()
  let original = try await h.reserve()
  let gate = CoordinatorGate()
  await h.store.configure(gate: gate, write: 2)
  let preparing = Task { try await h.prepare(original) }
  await gate.wait()
  #expect(await h.native.preparations == 0)
  #expect(await h.store.rows.first?.preparation == nil)
  await gate.release()
  let value = try await preparing.value
  #expect(value.reservation == original)
  #expect(await h.native.preparations == 1)
  try await h.journal.close()
}

@Test(arguments: [0, 1, 2]) func approvalMalformedPublicProofCannotBePersisted(field: Int)
  async throws
{
  let h = ApprovalHarness()
  let original = try await h.reserve()
  let value = PhoneOwnerApprovalPreparation(
    reservation: original,
    deviceKey: Data(repeating: 1, count: field == 0 ? 31 : 32),
    signature: Data(repeating: 2, count: field == 1 ? 63 : 64),
    digest: Data(repeating: 3, count: field == 2 ? 31 : 32))
  await h.native.configure(replacement: value)
  do {
    _ = try await h.prepare(original)
    Issue.record("Malformed native proof accepted")
  } catch let failure as PhoneOwnerApprovalFailure {
    #expect(failure.underlying as? PhoneOwnerApprovalRefusal == .invalid)
    #expect(failure.preparation == value)
  }
  #expect(await h.store.rows.first?.preparation == nil)
  try await h.journal.close()
}

@Test func approvalFailedPhysicalCloseIsSharedPermanentAndKeepsOriginalHistory() async throws {
  let h = ApprovalHarness()
  let original = try await h.reserve()
  await h.native.configure(failure: true)
  for _ in 0..<2 {
    await #expect(throws: ApprovalFault.native) { try await h.journal.close() }
  }
  #expect(await h.native.closes == 1)
  await #expect(throws: PhoneOwnerApprovalRefusal.closed) { _ = try await h.reserve() }
  #expect(try await h.journal.records().map(\.reservation) == [original])
}
