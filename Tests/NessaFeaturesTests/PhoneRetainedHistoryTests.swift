import Foundation
import NessaFeatures
import Testing

private func retainedHistorySnapshot() throws -> PhoneProfileSnapshot {
  let profile = exampleProfile(phase: .prepared).recording(
    pairingStatus: nil, nativeReceiver: "native-receiver",
    nativeStatus: coordinatorStatus(coordinatorReceipt(phase: .active)), recoveredPurge: nil,
    retired: false)
  return try .init(registry: exampleProfiles(profile), local: nil, nativeStatus: nil, source: nil)
}
private func retainedHistoryPage(
  _ ids: [String], next: RetainedEntryKey? = nil, generation: UInt64 = 4,
  receiver: String = "native-receiver"
) -> RetainedCataloguePage {
  .init(
    activeBoundary: nil, activeCursor: nil, completed: 8,
    entries: ids.map {
      .init(
        agent: "agent", archived: false, createdAtMs: 1, deleted: false,
        key: .init(creation: 1, id: $0),
        model: nil, preview: "preview", revision: 3, title: $0, updatedAtMs: 2)
    }, generation: generation, next: next,
    scope: .init(
      accessEpoch: "99", incarnation: "incarnation", origin: "origin", receiver: receiver,
      schema: "1", stream: "stream"))
}
private func scopedHistory(
  _ page: RetainedCataloguePage?, snapshot: PhoneProfileSnapshot,
  profile: UUID? = nil, revision: UUID? = nil
) -> PhoneScopedRetention<RetainedCataloguePage?> {
  .init(
    profileID: profile ?? snapshot.profile.id, revision: revision ?? snapshot.registry.revision,
    value: page)
}

@Test func retainedHistoryKeepsNativePagesAndOpaqueCursorContinuity() async throws {
  let snapshot = try retainedHistorySnapshot()
  let key = RetainedEntryKey(creation: UInt64.max, id: "é")
  let first = retainedHistoryPage(["a"], next: key)
  let second = retainedHistoryPage(["b"])
  let child = RuntimeSnapshotChild(value: snapshot)
  await child.configure(pages: [
    scopedHistory(first, snapshot: snapshot), scopedHistory(second, snapshot: snapshot),
  ])
  let result = try await PhoneRetainedHistory(session: child, pageSize: 1, maximumPages: 2)
    .catalogue(for: snapshot)
  #expect(result.pages == [first, second])
  #expect(result.list.conversations.map(\.id) == ["a", "b"])
  #expect(result.list.complete)
  #expect(await child.requestedKeys == [nil, key])
}

@Test func retainedHistoryRefusesMixedProfileRevisionScopeGenerationAndDuplicateKeys() async throws
{
  for mismatch in 0..<5 {
    let snapshot = try retainedHistorySnapshot()
    let key = RetainedEntryKey(creation: 3, id: "next")
    let first = retainedHistoryPage(["a"], next: key)
    let second = retainedHistoryPage(
      [mismatch == 4 ? "a" : "b"], generation: mismatch == 3 ? 5 : 4,
      receiver: mismatch == 2 ? "other" : "native-receiver")
    let child = RuntimeSnapshotChild(value: snapshot)
    await child.configure(pages: [
      scopedHistory(first, snapshot: snapshot),
      scopedHistory(
        second, snapshot: snapshot, profile: mismatch == 0 ? UUID() : nil,
        revision: mismatch == 1 ? UUID() : nil),
    ])
    do {
      _ = try await PhoneRetainedHistory(session: child).catalogue(for: snapshot)
      Issue.record("Mixed catalogue published")
    } catch let failure as PhoneRetainedHistoryFailure {
      #expect(failure.profileID == snapshot.profile.id)
      #expect(failure.pages.first == first)
      #expect(
        failure.underlying as? PhoneRetainedHistoryRefusal
          == (mismatch == 4 ? .invalidProjection : .changed))
    }
  }
}

@Test func retainedHistoryBoundsPaginationAndDoesNotMistakeAbsentForEmpty() async throws {
  let snapshot = try retainedHistorySnapshot()
  let key = RetainedEntryKey(creation: 3, id: "next")
  for repeated in [false, true] {
    let child = RuntimeSnapshotChild(value: snapshot)
    await child.configure(pages: [
      scopedHistory(retainedHistoryPage(["a"], next: key), snapshot: snapshot),
      scopedHistory(
        retainedHistoryPage(["b"], next: repeated ? key : .init(creation: 4, id: "later")),
        snapshot: snapshot),
    ])
    do {
      _ = try await PhoneRetainedHistory(session: child, maximumPages: 2).catalogue(for: snapshot)
      Issue.record("Unbounded pages published")
    } catch let error as PhoneRetainedHistoryFailure {
      #expect(
        error.underlying as? PhoneRetainedHistoryRefusal == (repeated ? .invalidProjection : .quota)
      )
    }
  }
  let absent = RuntimeSnapshotChild(value: snapshot)
  await absent.configure(pages: [scopedHistory(nil, snapshot: snapshot)])
  do {
    _ = try await PhoneRetainedHistory(session: absent).catalogue(for: snapshot)
    Issue.record("Absence became empty list")
  } catch let error as PhoneRetainedHistoryFailure {
    #expect(error.underlying as? PhoneRetainedHistoryRefusal == .unavailable)
  }
}

@Test func retainedHistoryPreservesUnavailableTranscriptFailureAndNativeBytes() async throws {
  let snapshot = try retainedHistorySnapshot()
  let scope = retainedHistoryPage([]).scope
  let epoch = UUID()
  let child = RuntimeSnapshotChild(value: snapshot)
  for outcome: RetainedViewOutcome in [
    .absent, .failed(.init(failure: .native(.cacheUncertain), json: nil)),
  ] {
    let transcript = RetainedTranscript(
      state: .retained, scope: scope, downloaded: 5, applied: 3, facts: 2,
      generation: 4, view: outcome)
    await child.configure(
      transcript: .init(
        profileID: snapshot.profile.id, revision: snapshot.registry.revision, value: transcript))
    do {
      _ = try await PhoneRetainedHistory(session: child).transcript(
        "a", for: snapshot, revision: epoch)
      Issue.record("Unavailable native view accepted")
    } catch let error as PhoneRetainedHistoryFailure {
      #expect(error.transcript == transcript)
      #expect(error.underlying as? PhoneRetainedHistoryRefusal == .unavailable)
    }
  }
  let bytes = Data("{\"native\":\"full document\"}".utf8)
  let display = try JSONDecoder().decode(
    NessaConversationView.self,
    from: Data(
      "{\"conversationId\":\"a\",\"messages\":[],\"permissions\":[],\"truncated\":false}".utf8))
  let projection = RetainedConversationProjection(
    json: bytes, revision: epoch.uuidString.lowercased() + ":3",
    revisionEpoch: epoch, display: display)
  let transcript = RetainedTranscript(
    state: .retained, scope: scope, downloaded: 5, applied: 3, facts: 2,
    generation: 4, view: .available(projection))
  await child.configure(
    transcript: .init(
      profileID: snapshot.profile.id, revision: snapshot.registry.revision, value: transcript))
  let result = try await PhoneRetainedHistory(session: child).transcript(
    "a", for: snapshot, revision: epoch)
  #expect(result.value == transcript)
  guard case .available(let retained) = result.value.view else {
    Issue.record("Missing projection")
    return
  }
  #expect(retained.json == bytes)
}

@Test func phoneRuntimeRealNativeSuspendReopensTheSameDirectory() async throws {
  let root = profileTestRoot()
  defer { try? FileManager.default.removeItem(at: root) }
  let profile = exampleProfile(phase: .prepared)
  let profiles = PhoneProfileStore(root: root)
  let preparing = exampleProfiles(profile.changingPhase(to: .preparing))
  try await profiles.save(preparing, replacing: nil)
  try await profiles.save(exampleProfiles(profile), replacing: preparing)
  let credentials = CoordinatorCredentials(profile)
  let locations = PhoneNativeLocations(root: root)
  let gateway = CoordinatorGateway(
    .init(
      connection: .init(),
      snapshot: .init(
        identity: profile.identity,
        expiresAt: nil, grants: [], methods: [])), status: coordinatorOwner())
  let runtime = PhoneSyncRuntime(
    profiles: profiles, credentials: credentials,
    factory: {
      PhoneProfileCoordinator(
        profiles: profiles, credentials: credentials, locations: locations,
        identity: gateway, pairing: gateway, factory: NativeRetainedSessionFactory(),
        withdrawal: CoordinatorWithdrawal())
    })
  let first = try #require(try await runtime.startup())
  try await runtime.suspend()
  let location = try await locations.prepare(profile)
  let other = try await NativeRetainedSessionFactory().open(location)
  #expect(try await other.localEnrollment() == nil)
  try await other.close()
  let second = try #require(try await runtime.startup())
  #expect(first.snapshot.profile.sameSetup(as: second.snapshot.profile))
  #expect(first.snapshot.registry.revision != second.snapshot.registry.revision)
  try await runtime.close()
  await #expect(throws: PhoneSyncRuntimeRefusal.closed) { _ = try await runtime.startup() }
}

@Test func coordinatorIdenticalFactsSkipIncidentalWritesButRestoreConfirmsDurability() async throws
{
  let harness = CoordinatorHarness()
  let coordinator = harness.coordinator()
  let first = try #require(try await coordinator.restore())
  let savedWrites = await harness.profiles.writes
  let observed = try await coordinator.refresh(on: nil)
  #expect(observed.registry == first.registry)
  #expect(await harness.profiles.writes == savedWrites)
  let restored = try #require(try await coordinator.restore())
  #expect(restored.registry.revision != first.registry.revision)
  #expect(await harness.profiles.writes == savedWrites + 1)
  try await coordinator.close()
}
