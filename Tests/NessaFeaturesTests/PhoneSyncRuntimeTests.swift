import Foundation
import NessaFeatures
import Testing

private final class RuntimeChildren: @unchecked Sendable {
  private let lock = NSLock()
  private var children: [any PhoneProfileCoordinating]
  private var constructed = 0
  init(_ children: [any PhoneProfileCoordinating]) { self.children = children }
  func make() -> any PhoneProfileCoordinating {
    lock.withLock {
      constructed += 1
      return children.removeFirst()
    }
  }
  var count: Int { lock.withLock { constructed } }
}
private actor RuntimeCredentials: PhoneProfileCredentialStoring {
  let value: String
  let gate: CoordinatorGate?
  var loads = 0
  init(value: String = "fixture", gate: CoordinatorGate? = nil) {
    self.value = value
    self.gate = gate
  }
  func load(reference: String) async -> String {
    loads += 1
    if let gate { await gate.pause() }
    return value
  }
  func insertOrVerify(_ credential: String, reference: String) {}
}
/// Public-port substitute: no private native handle escapes its actual coordinator owner.
actor RuntimeSnapshotChild: PhoneProfileCoordinating {
  let value: PhoneProfileSnapshot?
  let restoreGate: CoordinatorGate?
  let closeGate: CoordinatorGate?
  let failsClose: Bool
  var closes = 0
  var pageResults: [PhoneScopedRetention<RetainedCataloguePage?>] = []
  var transcriptResult: PhoneScopedRetention<RetainedTranscript>?
  var requestedKeys: [RetainedEntryKey?] = []
  func configure(
    pages: [PhoneScopedRetention<RetainedCataloguePage?>] = [],
    transcript: PhoneScopedRetention<RetainedTranscript>? = nil
  ) {
    pageResults = pages
    transcriptResult = transcript
  }
  init(
    value: PhoneProfileSnapshot?, restore: CoordinatorGate? = nil, close: CoordinatorGate? = nil,
    failsClose: Bool = false
  ) {
    self.value = value
    restoreGate = restore
    closeGate = close
    self.failsClose = failsClose
  }
  func restore() async -> PhoneProfileSnapshot? {
    if let restoreGate { await restoreGate.pause() }
    return value
  }
  func prepare(_ desired: PhoneProfile, credential: String, on lease: GatewayConnectionLease) throws
    -> PhoneProfileSnapshot
  { throw PhoneSyncRuntimeRefusal.unavailable }
  func startPairing(on lease: GatewayConnectionLease) throws -> PhoneProfileSnapshot {
    throw PhoneSyncRuntimeRefusal.unavailable
  }
  func resolveInvitation(_ invitation: Data, on lease: GatewayConnectionLease) throws
    -> PhoneProfileSnapshot
  { throw PhoneSyncRuntimeRefusal.unavailable }
  func discardUnenrolled() throws -> PhoneProfileSnapshot {
    throw PhoneSyncRuntimeRefusal.unavailable
  }
  func observePairing(on lease: GatewayConnectionLease) throws -> PhoneProfileSnapshot {
    throw PhoneSyncRuntimeRefusal.unavailable
  }
  func approve(_ confirmation: PhonePairingConfirmation, on lease: GatewayConnectionLease) throws
    -> PhoneProfileSnapshot
  { throw PhoneSyncRuntimeRefusal.unavailable }
  func cancelPairing(on lease: GatewayConnectionLease) throws -> PhoneProfileSnapshot {
    throw PhoneSyncRuntimeRefusal.unavailable
  }
  func refresh(on lease: GatewayConnectionLease?) throws -> PhoneProfileSnapshot {
    throw PhoneSyncRuntimeRefusal.unavailable
  }
  func cataloguePage(after: RetainedEntryKey?, maximum: UInt32) throws -> PhoneScopedRetention<
    RetainedCataloguePage?
  > {
    requestedKeys.append(after)
    guard !pageResults.isEmpty else { throw PhoneSyncRuntimeRefusal.unavailable }
    return pageResults.removeFirst()
  }
  func transcript(conversation: String, revision: UUID) throws -> PhoneScopedRetention<
    RetainedTranscript
  > {
    guard let transcriptResult else { throw PhoneSyncRuntimeRefusal.unavailable }
    return transcriptResult
  }
  func close() async throws {
    closes += 1
    if let closeGate { await closeGate.pause() }
    if failsClose { throw CoordinatorFixtureError.close }
  }
}
private func runtimeSnapshot(_ profile: PhoneProfile = exampleProfile(phase: .prepared)) throws
  -> PhoneProfileSnapshot
{
  try .init(registry: exampleProfiles(profile), local: nil, nativeStatus: nil, source: nil)
}

@Test func phoneRuntimeStartupUsesOnlyItsPreparedProfileCredential() async throws {
  let harness = CoordinatorHarness()
  let runtime = PhoneSyncRuntime(
    profiles: harness.profiles, credentials: harness.credentials, factory: { harness.coordinator() }
  )
  let startup = try #require(try await runtime.startup())
  #expect(startup.snapshot.profile.id == harness.profile.id)
  #expect(startup.connection?.credential == "fixture")
  #expect(startup.connection?.address == harness.profile.productAddress)
  #expect(startup.connection?.instance == harness.profile.instance)
  #expect(await harness.factory.opens == 1)
  try await runtime.close()
}

@Test func phoneRuntimeSuspendJoinsCancelledWaiterAndCannotPublishLateCredential() async throws {
  let snapshot = try runtimeSnapshot()
  let reading = CoordinatorGate()
  let draining = CoordinatorGate()
  let child = RuntimeSnapshotChild(value: snapshot, close: draining)
  let replacement = RuntimeSnapshotChild(value: snapshot)
  let children = RuntimeChildren([child, replacement])
  let credentials = RuntimeCredentials(gate: reading)
  let runtime = PhoneSyncRuntime(
    profiles: CoordinatorProfiles(snapshot.registry), credentials: credentials,
    factory: { children.make() })
  let startup = Task { try await runtime.startup() }
  await reading.wait()
  let first = Task { try await runtime.suspend() }
  await draining.wait()
  first.cancel()
  let second = Task { try await runtime.suspend() }
  await #expect(throws: PhoneSyncRuntimeRefusal.suspended) { _ = try await runtime.restore() }
  #expect(children.count == 1)
  #expect(await child.closes == 1)
  await draining.release()
  // Physical child close finished, but the admitted wrapper still holds credential work.
  await #expect(throws: PhoneSyncRuntimeRefusal.suspended) { _ = try await runtime.restore() }
  #expect(children.count == 1)
  await reading.release()
  do {
    _ = try await startup.value
    Issue.record("Late credential was published")
  } catch let failure as PhoneSyncRuntimeFailure {
    #expect(failure.snapshot?.profile.id == snapshot.profile.id)
    #expect(failure.underlying as? PhoneSyncRuntimeRefusal == .suspended)
  }
  try await first.value
  try await second.value
  _ = try await runtime.restore()
  #expect(children.count == 2)
  try await runtime.close()
}

@Test func phoneRuntimeFailedDrainNeverConstructsReplacementAndFinalCloseIsPermanent() async throws
{
  let snapshot = try runtimeSnapshot()
  let child = RuntimeSnapshotChild(value: snapshot, failsClose: true)
  let children = RuntimeChildren([child, RuntimeSnapshotChild(value: snapshot)])
  let runtime = PhoneSyncRuntime(
    profiles: CoordinatorProfiles(snapshot.registry), credentials: RuntimeCredentials(),
    factory: { children.make() })
  _ = try await runtime.restore()
  for _ in 0..<2 {
    await #expect(throws: CoordinatorFixtureError.close) { try await runtime.suspend() }
  }
  await #expect(throws: PhoneSyncRuntimeRefusal.suspended) { _ = try await runtime.restore() }
  #expect(children.count == 1)
  #expect(await child.closes == 1)
  await #expect(throws: CoordinatorFixtureError.close) { try await runtime.close() }
  await #expect(throws: PhoneSyncRuntimeRefusal.closed) { _ = try await runtime.restore() }
}

@Test func phoneRuntimeChangedProfileDuringCredentialLoadCannotHandoffOldAccount() async throws {
  let snapshot = try runtimeSnapshot()
  let gate = CoordinatorGate()
  let profiles = CoordinatorProfiles(snapshot.registry)
  let runtime = PhoneSyncRuntime(
    profiles: profiles, credentials: RuntimeCredentials(gate: gate),
    factory: { RuntimeSnapshotChild(value: snapshot) })
  let starting = Task { try await runtime.startup() }
  await gate.wait()
  await profiles.replaceExternally(exampleProfiles(exampleProfile(phase: .prepared)))
  await gate.release()
  do {
    _ = try await starting.value
    Issue.record("Old account handed off")
  } catch let error as PhoneSyncRuntimeFailure {
    #expect(error.snapshot?.profile.id == snapshot.profile.id)
    #expect(error.underlying as? PhoneSyncRuntimeRefusal == .changed)
  }
  try await runtime.close()
}

@Test func phoneRuntimeRetiredProfileHasNoProductCredentialHandoff() async throws {
  let profile = exampleProfile(phase: .prepared).recording(
    pairingStatus: nil, nativeReceiver: nil, nativeStatus: nil,
    recoveredPurge: nil, retired: true, retirementReason: .userDiscarded)
  let snapshot = try runtimeSnapshot(profile)
  let credentials = RuntimeCredentials()
  let runtime = PhoneSyncRuntime(
    profiles: CoordinatorProfiles(snapshot.registry), credentials: credentials,
    factory: { RuntimeSnapshotChild(value: snapshot) })
  let result = try #require(try await runtime.startup())
  #expect(result.snapshot.profile.phase == .retired && result.connection == nil)
  #expect(await credentials.loads == 0)
  try await runtime.close()
}

@Test func phoneRuntimeMissingProfileIsLegacyOnlyWhenRegistryIsStillAbsent() async throws {
  let profiles = CoordinatorProfiles(nil)
  let gate = CoordinatorGate()
  let credentials = RuntimeCredentials()
  let child = RuntimeSnapshotChild(value: nil, restore: gate)
  let runtime = PhoneSyncRuntime(profiles: profiles, credentials: credentials, factory: { child })
  let startup = Task { try await runtime.startup() }
  await gate.wait()
  await profiles.replaceExternally(exampleProfiles(exampleProfile(phase: .prepared)))
  await gate.release()
  do {
    _ = try await startup.value
    Issue.record("New native profile mistaken for absent")
  } catch let error as PhoneSyncRuntimeFailure {
    #expect(error.underlying as? PhoneSyncRuntimeRefusal == .changed)
  }
  #expect(await credentials.loads == 0)
  try await runtime.close()
}

@Test func phoneRuntimePreparingSnapshotCannotHandOffAProductCredential() async throws {
  let snapshot = try runtimeSnapshot(exampleProfile())
  let credentials = RuntimeCredentials()
  let runtime = PhoneSyncRuntime(
    profiles: CoordinatorProfiles(snapshot.registry), credentials: credentials,
    factory: { RuntimeSnapshotChild(value: snapshot) })
  do {
    _ = try await runtime.startup()
    Issue.record("Preparing profile handed off credential")
  } catch let error as PhoneSyncRuntimeFailure {
    #expect(error.snapshot?.profile.phase == .preparing)
    #expect(error.underlying as? PhoneSyncRuntimeRefusal == .preparationRequired)
  }
  #expect(await credentials.loads == 0)
  try await runtime.close()
}
