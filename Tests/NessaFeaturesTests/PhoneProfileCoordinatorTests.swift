import Foundation
import NessaFeatures
import Testing

private func refusal(
  _ operation: () async throws -> Void, _ expected: PhoneProfileCoordinationRefusal
) async {
  do {
    try await operation()
    Issue.record("Expected refusal \(expected)")
  } catch let value as PhoneProfileCoordinationFailure {
    #expect(value.underlying as? PhoneProfileCoordinationRefusal == expected)
  } catch { #expect(error as? PhoneProfileCoordinationRefusal == expected) }
}

@Test func coordinatorLostCreatePersistsUncertaintyAndColdReopenDoesNotCreateAgain() async throws {
  let harness = CoordinatorHarness()
  let coordinator = harness.coordinator()
  _ = try await coordinator.restore()
  await harness.gateway.configure(lostCreate: true)
  do {
    _ = try await coordinator.startPairing(on: harness.lease)
    Issue.record("Expected lost answer")
  } catch let error as PhoneProfileCoordinationFailure {
    #expect(error.source?.connection == harness.lease)
    #expect(error.profileID == harness.profile.id)
    #expect(error.underlying is CoordinatorFixtureError)
  }
  let saved = try #require(await harness.profiles.load())
  #expect(saved.profiles[0].creationAttempt != nil && saved.profiles[0].pairingStatus == nil)
  #expect(await harness.gateway.creates == 1)
  try await coordinator.close()
  // A fresh native owner models restart, while public metadata and gateway survive.
  let freshNative = CoordinatorNative()
  let reopened = PhoneProfileCoordinator(
    profiles: harness.profiles, credentials: harness.credentials,
    locations: CoordinatorLocations(), identity: harness.gateway, pairing: harness.gateway,
    factory: CoordinatorFactory(freshNative), withdrawal: harness.withdrawal)
  _ = try await reopened.restore()
  await refusal(
    { _ = try await reopened.startPairing(on: harness.lease) }, .knownInvitationNeedsRecovery)
  #expect(await harness.gateway.creates == 1)
  #expect(await freshNative.enrolls == 0)
  try await reopened.close()
}

@Test func coordinatorMetadataFailureBeforeCreateAndBeforeEnrollStopsExternalEffects() async throws
{
  for fault: CoordinatorProfiles.Fault in [.creation, .owner] {
    let harness = CoordinatorHarness()
    let coordinator = harness.coordinator()
    _ = try await coordinator.restore()
    await harness.profiles.configure(fault)
    do {
      _ = try await coordinator.startPairing(on: harness.lease)
      Issue.record("Expected save failure")
    } catch let error as PhoneProfileCoordinationFailure {
      #expect(error.underlying is CoordinatorFixtureError)
      #expect((error.owner != nil) == (fault == .owner))
    }
    #expect(await harness.gateway.creates == (fault == .creation ? 0 : 1))
    #expect(await harness.native.enrolls == 0)
    await refusal(
      { _ = try await coordinator.startPairing(on: harness.lease) }, .knownInvitationNeedsRecovery)
    try await coordinator.close()
  }
}

@Test func coordinatorApprovalRequiresExactDisplayedClaimAndFreshOwnerFacts() async throws {
  let harness = CoordinatorHarness()
  let coordinator = harness.coordinator()
  _ = try await coordinator.restore()
  _ = try await coordinator.startPairing(on: harness.lease)
  await harness.gateway.changeStatus(coordinatorOwner(phase: .claimed))
  let claimed = try await coordinator.observePairing(on: harness.lease)
  let confirmation = try #require(claimed.confirmation)
  let wrong = PhonePairingConfirmation(
    profileID: confirmation.profileID, invitation: confirmation.invitation,
    deviceKey: Data(repeating: 9, count: 32))
  await refusal(
    { _ = try await coordinator.approve(wrong, on: harness.lease) }, .confirmationChanged)
  #expect(await harness.gateway.approvals == 0)
  await harness.gateway.changeStatus(coordinatorOwner(phase: .claimed, className: "other"))
  await refusal(
    { _ = try await coordinator.approve(confirmation, on: harness.lease) }, .correlationChanged)
  #expect(await harness.gateway.approvals == 0)
  await harness.gateway.changeStatus(coordinatorOwner(phase: .claimed))
  let approved = try await coordinator.approve(confirmation, on: harness.lease)
  #expect(approved.activationStopped == .retryable)
  #expect(await harness.gateway.approvals == 1)
  try await coordinator.close()
}

@Test func coordinatorExplicitRecoveryCannotRetargetLocalClaimAndDiscardDoesNotInventTerminal()
  async throws
{
  let harness = CoordinatorHarness()
  let coordinator = harness.coordinator()
  _ = try await coordinator.restore()
  await harness.gateway.configure(lostCreate: true)
  do { _ = try await coordinator.startPairing(on: harness.lease) } catch {}
  let selected = try await coordinator.resolveInvitation(
    coordinatorIntent().invitation, on: harness.lease)
  #expect(selected.profile.pairingStatus?.invitationID == coordinatorIntent().invitation)
  #expect(selected.local == nil && selected.confirmation == nil)
  await refusal(
    { _ = try await coordinator.startPairing(on: harness.lease) }, .knownInvitationNeedsRecovery)
  let discarded = try await coordinator.discardUnenrolled()
  #expect(
    discarded.profile.phase == .retired && discarded.profile.retirementReason == .userDiscarded)
  #expect(discarded.profile.lastNativeStatus == nil && discarded.profile.recoveredPurge == nil)
  #expect(discarded.profile.pairingStatus?.phase == .available)
  #expect(await harness.withdrawal.scopes.count == 1)
  try await coordinator.close()

  let claimed = CoordinatorHarness(
    local: coordinatorLocal(issued: false),
    status: coordinatorStatus(coordinatorReceipt(phase: .claimed)))
  let another = claimed.coordinator()
  _ = try await another.restore()
  await refusal(
    { _ = try await another.resolveInvitation(coordinatorIntent().invitation, on: claimed.lease) },
    .knownInvitationNeedsRecovery)
  await refusal({ _ = try await another.discardUnenrolled() }, .knownInvitationNeedsRecovery)
  #expect(await claimed.withdrawal.scopes.isEmpty)
  try await another.close()
}

@Test func coordinatorReceiverMustBeDurableBeforeAnyRetainedRead() async throws {
  let harness = CoordinatorHarness(
    local: coordinatorLocal(issued: true),
    status: coordinatorStatus(coordinatorReceipt(phase: .active)))
  await harness.profiles.configure(.receiver)
  let coordinator = harness.coordinator()
  do {
    _ = try await coordinator.restore()
    Issue.record("Expected receiver save failure")
  } catch {}
  await refusal(
    { _ = try await coordinator.cataloguePage(after: nil, maximum: 20) },
    .knownInvitationNeedsRecovery)
  #expect(await harness.native.reads == 0)
  await harness.profiles.configure(nil)
  let recovered = try #require(try await coordinator.restore())
  #expect(recovered.profile.nativeReceiver == "native-receiver")
  let page = try await coordinator.cataloguePage(after: nil, maximum: 20)
  #expect(page.profileID == harness.profile.id)
  #expect(await harness.native.reads == 1)
  try await coordinator.close()
}

@Test func coordinatorTerminalSaveSurvivesWithdrawalFailureAndRecordRemoval() async throws {
  let harness = CoordinatorHarness(
    local: coordinatorLocal(issued: true),
    status: coordinatorStatus(coordinatorReceipt(phase: .active)))
  let coordinator = harness.coordinator()
  _ = try await coordinator.restore()
  await harness.withdrawal.configure(fail: true)
  await harness.native.configure(
    local: nil, status: coordinatorStatus(coordinatorReceipt(phase: .terminal)))
  do {
    _ = try await coordinator.refresh(on: nil)
    Issue.record("Expected withdrawal failure")
  } catch let error as PhoneProfileCoordinationFailure {
    #expect(error.nativeStatus?.receipt?.phase == .terminal)
  }
  let captured = try #require(await harness.profiles.load())
  #expect(captured.profiles[0].phase == .prepared)
  #expect(captured.profiles[0].nativeReceiver == "native-receiver")
  #expect(captured.profiles[0].lastNativeStatus?.receipt?.phase == .terminal)
  #expect(await harness.native.reads == 0)
  try await coordinator.close()
  await harness.withdrawal.configure(fail: false)
  let fresh = CoordinatorNative()
  await fresh.configure(
    local: nil, status: coordinatorStatus(),
    purge: .init(
      catalogueEntries: 2, observedAtMs: 300,
      receiver: "native-receiver", records: 1, transcripts: 1))
  let reopened = PhoneProfileCoordinator(
    profiles: harness.profiles, credentials: harness.credentials,
    locations: CoordinatorLocations(), identity: harness.gateway, pairing: harness.gateway,
    factory: CoordinatorFactory(fresh), withdrawal: harness.withdrawal)
  let retired = try #require(try await reopened.restore())
  #expect(retired.profile.phase == .retired)
  #expect(retired.profile.recoveredPurge?.receiver == "native-receiver")
  await refusal({ _ = try await reopened.cataloguePage(after: nil, maximum: 20) }, .retired)
  #expect(await fresh.reads == 0)
  try await reopened.close()
}

@Test func coordinatorChangedLeaseCannotPublishAnOldCreationAnswer() async throws {
  let harness = CoordinatorHarness()
  let coordinator = harness.coordinator()
  _ = try await coordinator.restore()
  let gate = CoordinatorGate()
  await harness.gateway.configure(gate: gate)
  let starting = Task { try await coordinator.startPairing(on: harness.lease) }
  await gate.wait()
  let changed = AuthenticatedGatewaySession(
    connection: .init(),
    snapshot: .init(identity: harness.profile.identity, expiresAt: nil, grants: [], methods: []))
  await harness.gateway.changeSource(changed)
  await gate.release()
  do {
    _ = try await starting.value
    Issue.record("Expected changed source")
  } catch let error as PhoneProfileCoordinationFailure {
    #expect(error.source?.connection == harness.lease)
    #expect(error.owner != nil)
    #expect(error.underlying as? PhoneProfileCoordinationRefusal == .receiptSourceChanged)
  }
  #expect(await harness.native.enrolls == 0)
  #expect(await harness.profiles.load()?.profiles[0].pairingStatus == nil)
  try await coordinator.close()
}

@Test func coordinatorCancelledFirstCloseStillDrainsAndRepeatedCloseJoins() async throws {
  let harness = CoordinatorHarness()
  let coordinator = harness.coordinator()
  _ = try await coordinator.restore()
  let capture = CoordinatorGate()
  let draining = CoordinatorGate()
  await harness.native.hold(close: draining, capture: capture)
  let operation = Task { try await coordinator.refresh(on: nil) }
  await capture.wait()
  let firstClose = Task { try await coordinator.close() }
  await draining.wait()
  firstClose.cancel()
  let secondClose = Task { try await coordinator.close() }
  await refusal({ _ = try await coordinator.restore() }, .closed)
  #expect(await harness.native.closes == 1)
  await draining.release()
  await capture.release()
  do {
    _ = try await operation.value
    Issue.record("Closed operation published")
  } catch {}
  try await firstClose.value
  try await secondClose.value
  #expect(await harness.native.closed)
  #expect(await harness.native.closes == 1)
}

@Test func coordinatorCloseDrainsLateConstructionAndRefusesNewAdmission() async throws {
  let opening = CoordinatorGate()
  let draining = CoordinatorGate()
  let harness = CoordinatorHarness(openingGate: opening)
  await harness.native.hold(close: draining)
  let coordinator = harness.coordinator()
  let restoring = Task { try await coordinator.restore() }
  await opening.wait()
  let first = Task { try await coordinator.close() }
  var fenced = false
  for _ in 0..<100 {
    do { _ = try await coordinator.restore() } catch let error as PhoneProfileCoordinationRefusal {
      if error == .closed {
        fenced = true
        break
      }
    } catch {}
    await Task.yield()
  }
  #expect(fenced)
  first.cancel()
  let second = Task { try await coordinator.close() }
  await opening.release()
  await draining.wait()
  #expect(await harness.native.closes == 1)
  await draining.release()
  do {
    _ = try await restoring.value
    Issue.record("Late construction published")
  } catch {}
  try await first.value
  try await second.value
  #expect(await harness.native.closed)
}

@Test func coordinatorFailedPhysicalCloseIsPreservedAndNeverReopens() async throws {
  let harness = CoordinatorHarness()
  let coordinator = harness.coordinator()
  _ = try await coordinator.restore()
  await harness.native.hold(failClose: true)
  for _ in 0..<2 {
    do {
      try await coordinator.close()
      Issue.record("Failed close passed")
    } catch let failure as PhoneProfileCloseFailure {
      #expect(failure.failures.count == 1 && failure.failures[0].profileID == harness.profile.id)
    }
  }
  #expect(await harness.native.closes == 1)
  await refusal({ _ = try await coordinator.restore() }, .closed)
  #expect(await harness.factory.opens == 1)
}

@Test func coordinatorRealNativeLateOpenDrainsBeforeSameDirectoryReopen() async throws {
  let root = profileTestRoot()
  try FileManager.default.createDirectory(
    at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
  defer { try? FileManager.default.removeItem(at: root) }
  let profile = exampleProfile(phase: .prepared)
  let profiles = CoordinatorProfiles(exampleProfiles(profile))
  let credentials = CoordinatorCredentials(profile)
  let locations = PhoneNativeLocations(root: root)
  let gateway = CoordinatorGateway(
    .init(
      connection: .init(),
      snapshot: .init(
        identity: profile.identity,
        expiresAt: nil, grants: [], methods: [])), status: coordinatorOwner())
  let opened = CoordinatorGate()
  let factory = HeldRealCoordinatorFactory(gate: opened)
  let coordinator = PhoneProfileCoordinator(
    profiles: profiles, credentials: credentials, locations: locations,
    identity: gateway, pairing: gateway, factory: factory, withdrawal: CoordinatorWithdrawal())
  let restore = Task { try await coordinator.restore() }
  await opened.wait()
  let location = try await locations.prepare(profile)
  let closing = Task { try await coordinator.close() }
  var fenced = false
  for _ in 0..<100 {
    do { _ = try await coordinator.restore() } catch let refusal as PhoneProfileCoordinationRefusal
    {
      if refusal == .closed {
        fenced = true
        break
      }
    } catch {}
    await Task.yield()
  }
  #expect(fenced)
  closing.cancel()
  let joined = Task { try await coordinator.close() }
  await opened.release()
  do {
    _ = try await restore.value
    Issue.record("Closed restore published")
  } catch {}
  try await closing.value
  try await joined.value
  let fresh = try await NativeRetainedSessionFactory().open(location)
  #expect(try await fresh.localEnrollment() == nil)
  try await fresh.close()
}

private struct HeldRealCoordinatorFactory: RetainedSessionFactory {
  let gate: CoordinatorGate
  func open(_ location: RetainedSessionLocation) async throws -> any RetainedSession {
    let session = try await NativeRetainedSessionFactory().open(location)
    await gate.pause()
    return session
  }
}

@Test func coordinatorExistingMetadataDecodesWithoutInventedPairingAndSelectorsCannotChange() throws
{
  let profile = exampleProfile(phase: .prepared)
  let original = exampleProfiles(profile)
  let data = try JSONEncoder().encode(original)
  let decoded = try JSONDecoder().decode(PhoneProfiles.self, from: data)
  #expect(decoded == original)
  #expect(decoded.profiles[0].creationAttempt == nil && decoded.profiles[0].retirementReason == nil)
  #expect(decoded.profiles[0].pairingStatus == nil && decoded.profiles[0].lastNativeStatus == nil)
  let attempt = UUID()
  let bound = profile.recording(
    pairingStatus: coordinatorOwner(), nativeReceiver: nil, nativeStatus: nil,
    recoveredPurge: nil, retired: false, creationAttempt: attempt)
  let saved = PhoneProfiles(revision: UUID(), selected: profile.id, profiles: [bound])
  try saved.validate(replacing: original)
  #expect(try JSONDecoder().decode(PhoneProfiles.self, from: JSONEncoder().encode(saved)) == saved)
  let retargeted = bound.recording(
    pairingStatus: coordinatorOwner(className: "different"), nativeReceiver: nil,
    nativeStatus: nil, recoveredPurge: nil, retired: false)
  #expect(throws: PhoneProfileStoreError.invalid) {
    try PhoneProfiles(revision: UUID(), selected: profile.id, profiles: [retargeted]).validate(
      replacing: saved)
  }
  let changedAttempt = bound.recording(
    pairingStatus: bound.pairingStatus, nativeReceiver: nil, nativeStatus: nil,
    recoveredPurge: nil, retired: false, creationAttempt: UUID())
  #expect(throws: PhoneProfileStoreError.invalid) {
    try PhoneProfiles(revision: UUID(), selected: profile.id, profiles: [changedAttempt]).validate(
      replacing: saved)
  }
  let discarded = bound.recording(
    pairingStatus: bound.pairingStatus, nativeReceiver: nil, nativeStatus: nil,
    recoveredPurge: nil, retired: true, retirementReason: .userDiscarded)
  let retired = PhoneProfiles(revision: UUID(), selected: profile.id, profiles: [discarded])
  try retired.validate(replacing: saved)
  #expect(throws: PhoneProfileStoreError.invalid) {
    try PhoneProfiles(
      revision: UUID(), selected: profile.id, profiles: [discarded.changingPhase(to: .prepared)]
    )
    .validate(replacing: retired)
  }
  #expect(throws: PhoneProfileStoreError.invalid) {
    try PhoneProfileSnapshot(
      registry: .init(revision: UUID(), selected: UUID(), profiles: []), local: nil,
      nativeStatus: nil, source: nil)
  }
}

@Test func coordinatorInitialIssuedReceiverSaveFailurePreventsTerminalStatusEffects() async throws {
  let harness = CoordinatorHarness(
    local: coordinatorLocal(issued: true),
    status: coordinatorStatus(coordinatorReceipt(phase: .terminal)))
  let coordinator = harness.coordinator()
  await harness.profiles.configure(.receiver)
  do {
    _ = try await coordinator.restore()
    Issue.record("Expected receiver save failure")
  } catch {}
  #expect(await harness.native.statuses == 0)
  #expect(await harness.native.refreshes == 0)
  #expect(await harness.withdrawal.scopes.isEmpty)
  #expect(await harness.profiles.load()?.profiles[0].nativeReceiver == nil)
  await harness.profiles.configure(nil)
  let terminal = try #require(try await coordinator.restore())
  #expect(terminal.profile.nativeReceiver == "native-receiver")
  #expect(terminal.profile.phase == .retired)
  #expect(await harness.native.statuses == 1)
  #expect(await harness.withdrawal.scopes.count == 1)
  try await coordinator.close()
}

@Test func coordinatorCompoundRefreshAndSaveFailureKeepIndependentEvidence() async throws {
  let harness = CoordinatorHarness(
    local: coordinatorLocal(issued: true),
    status: coordinatorStatus(coordinatorReceipt(phase: .active)))
  let coordinator = harness.coordinator()
  _ = try await coordinator.restore()
  let initial = coordinatorStatus(coordinatorReceipt(phase: .active))
  let recheck = coordinatorStatus(coordinatorReceipt(phase: .approved))
  let compound = RetainedRefresh(
    initial: initial,
    read: .init(
      complete: false, conversations: 2, failure: .cacheUncertain, moved: true,
      withdrawn: ["old-chat"]),
    recheck: recheck,
    selectionFailure: .init(
      crypto: nil, ioDiagnostic: "fixture", kind: .wire,
      storage: nil, wire: .init(correlation: .conflict, kind: .correlation), worker: nil))
  await harness.native.setRefresh(compound)
  let result = try await coordinator.refresh(on: nil)
  #expect(result.nativeRefresh == compound)
  #expect(result.nativeStatus == recheck)
  #expect(result.nativeRefresh?.initial == initial)
  #expect(result.nativeRefresh?.read?.withdrawn == ["old-chat"])
  await harness.profiles.configure(.nativeStatus)
  // Change a public receipt fact so this operation requires a real metadata publication.
  let later = coordinatorStatus(coordinatorReceipt(phase: .staging))
  let failedCompound = RetainedRefresh(
    initial: initial, read: compound.read, recheck: later,
    selectionFailure: compound.selectionFailure)
  await harness.native.setRefresh(failedCompound)
  do {
    _ = try await coordinator.refresh(on: nil)
    Issue.record("Expected post-refresh save failure")
  } catch let failure as PhoneProfileCoordinationFailure {
    #expect(failure.nativeRefresh == failedCompound)
    #expect(failure.nativeStatus == later)
    #expect(failure.local == coordinatorLocal(issued: true))
  }
  try await coordinator.close()
}

@Test func coordinatorExternalProfileSelectionPreventsLateOwnerPublication() async throws {
  let harness = CoordinatorHarness()
  let coordinator = harness.coordinator()
  _ = try await coordinator.restore()
  let gate = CoordinatorGate()
  await harness.gateway.configure(gate: gate)
  let starting = Task { try await coordinator.startPairing(on: harness.lease) }
  await gate.wait()
  let saved = try #require(await harness.profiles.load())
  let other = exampleProfile(phase: .prepared)
  let changed = PhoneProfiles(
    revision: UUID(), selected: other.id, profiles: saved.profiles + [other])
  await harness.profiles.replaceExternally(changed)
  await gate.release()
  do {
    _ = try await starting.value
    Issue.record("Old creation published")
  } catch let failure as PhoneProfileCoordinationFailure {
    #expect(failure.profileID == harness.profile.id)
    #expect(failure.source?.connection == harness.lease)
    #expect(failure.underlying as? PhoneProfileCoordinationRefusal == .profileChanged)
  }
  #expect(await harness.profiles.load() == changed)
  #expect(await harness.native.enrolls == 0)
  try await coordinator.close()
}

@Test func coordinatorRefreshCannotHideConflictingIntentAfterRemovingLocalState() async throws {
  for conflictingInitial in [false, true] {
    let harness = CoordinatorHarness(
      local: coordinatorLocal(issued: true),
      status: coordinatorStatus(coordinatorReceipt(phase: .active)))
    let coordinator = harness.coordinator()
    _ = try await coordinator.restore()
    let terminal = coordinatorReceipt(phase: .terminal)
    let intent = terminal.publicIntent
    let altered = RetainedPublicIntent(
      attempt: Data(repeating: 9, count: 16), consent: intent.consent,
      consentClass: intent.consentClass, consentClassName: intent.consentClassName,
      expiryMs: intent.expiryMs,
      generation: intent.generation, invitation: intent.invitation)
    let other = RetainedEnrollmentReceipt(
      accessEpoch: terminal.accessEpoch, attemptFailure: terminal.attemptFailure,
      attemptState: terminal.attemptState, audience: terminal.audience,
      credential: terminal.credential,
      organization: terminal.organization, phase: terminal.phase, publicIntent: altered,
      receiver: terminal.receiver,
      resource: terminal.resource, terminalCause: terminal.terminalCause)
    let compound = RetainedRefresh(
      initial: coordinatorStatus(other), read: nil,
      recheck: conflictingInitial ? coordinatorStatus(terminal) : nil, selectionFailure: nil)
    await harness.native.setRefresh(compound, removeLocal: true)
    do {
      _ = try await coordinator.refresh(on: nil)
      Issue.record("Conflicting native intent retired the profile")
    } catch let failure as PhoneProfileCoordinationFailure {
      #expect(failure.underlying as? PhoneProfileCoordinationRefusal == .correlationChanged)
      #expect(failure.nativeRefresh == compound)
      #expect(failure.local == coordinatorLocal(issued: true))
    }
    #expect(await harness.withdrawal.scopes.isEmpty)
    #expect(await harness.profiles.load()?.profiles[0].phase == .prepared)
    #expect(await harness.profiles.load()?.profiles[0].lastNativeStatus?.receipt?.phase == .active)
    // The original terminal intent remains legitimate despite the now absent private record.
    await harness.native.configure(
      local: coordinatorLocal(issued: true), status: coordinatorStatus(terminal))
    await harness.native.setRefresh(
      .init(
        initial: coordinatorStatus(terminal), read: nil, recheck: nil,
        selectionFailure: nil), removeLocal: true)
    let retired = try await coordinator.refresh(on: nil)
    #expect(retired.profile.phase == .retired)
    #expect(await harness.withdrawal.scopes.count == 1)
    try await coordinator.close()
  }
}

@Test func coordinatorNewSetupUsesItsOwnLeaseAndRetainsTheOldAccountProfile() async throws {
  let harness = CoordinatorHarness()
  let secondNative = CoordinatorNative()
  let factory = PerProfileCoordinatorFactory(
    old: harness.native, next: secondNative, oldDirectory: harness.profile.nativeDirectory)
  let switching = PhoneProfileCoordinator(
    profiles: harness.profiles, credentials: harness.credentials,
    locations: CoordinatorLocations(), identity: harness.gateway, pairing: harness.gateway,
    factory: factory, withdrawal: harness.withdrawal)
  _ = try await switching.restore()
  let old = try #require(await harness.profiles.load())
  let desired = PhoneProfile(
    id: UUID(), productAddress: "ws://127.0.0.1:28888/session", instance: "second",
    nativeAddress: "127.0.0.1:28889",
    identity: profileIdentity(Array(repeating: "second", count: 6)))
  let lease = GatewayConnectionLease()
  let source = AuthenticatedGatewaySession(
    connection: lease,
    snapshot: .init(
      identity: desired.identity,
      expiresAt: nil, grants: [], methods: []))
  await harness.gateway.changeSource(source)
  let selected = try await switching.prepare(desired, credential: "second-fixture", on: lease)
  #expect(
    selected.profile.id == desired.id && selected.profile.identity == source.snapshot.identity)
  #expect(selected.registry.profiles.first { $0.id == harness.profile.id } == old.profiles[0])
  #expect(selected.registry.profiles.count == 2)
  #expect(await harness.native.reads == 0)
  #expect(await harness.native.closes == 1)
  #expect(await secondNative.statuses == 1)
  await refusal(
    { _ = try await switching.observePairing(on: harness.lease) }, .receiptSourceChanged)
  try await switching.close()
}

private actor PerProfileCoordinatorFactory: RetainedSessionFactory {
  let old: any RetainedSession
  let next: any RetainedSession
  let oldDirectory: String
  init(old: any RetainedSession, next: any RetainedSession, oldDirectory: String) {
    self.old = old
    self.next = next
    self.oldDirectory = oldDirectory
  }
  func open(_ location: RetainedSessionLocation) -> any RetainedSession {
    location.directory == oldDirectory ? old : next
  }
}
