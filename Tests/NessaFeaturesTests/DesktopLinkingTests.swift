import Foundation
import Testing

@testable import NessaFeatures

private let mac = FoundGateway(name: "Studio", gateway: "gw-1", address: "192.168.1.20:47650")

private func receipt(
  _ phase: RetainedEnrollmentPhase, receiver: String? = nil, expiry: UInt64 = 10_000,
  attempt: RetainedAttemptState? = nil, failure: RetainedAttemptFailure? = nil,
  cause: RetainedTerminalCause? = nil
) -> RetainedEnrollmentReceipt {
  RetainedEnrollmentReceipt(
    accessEpoch: nil, attemptFailure: failure, attemptState: attempt, audience: "gw-1",
    credential: nil, organization: nil, phase: phase,
    publicIntent: RetainedPublicIntent(
      attempt: Data([1]), consent: Data([2]), consentClass: .deviceRead,
      consentClassName: "device_read", expiryMs: expiry, generation: 1, invitation: Data([3])),
    receiver: receiver, resource: nil, terminalCause: cause)
}

private func statusOf(_ receipt: RetainedEnrollmentReceipt) -> RetainedStatus {
  RetainedStatus(
    completionCaptured: false, failure: nil, purge: nil, purgeAttempted: false,
    purgeFailure: nil, receipt: receipt)
}

/// A native session that answers enroll, then each status in turn.
private actor Native: RetainedSession {
  var enrolled: [String] = []
  var statuses: [RetainedStatus]
  let first: RetainedEnrollmentReceipt
  var pages: [RetainedCataloguePage?] = []
  var transcriptView: RetainedTranscript?
  var closes = 0
  init(first: RetainedEnrollmentReceipt, then statuses: [RetainedStatus] = []) {
    self.first = first
    self.statuses = statuses
  }
  func setPages(_ pages: [RetainedCataloguePage?]) { self.pages = pages }
  func setTranscript(_ value: RetainedTranscript) { transcriptView = value }
  func localEnrollment() -> RetainedLocalEnrollment? { nil }
  func enroll(code: String) -> RetainedEnrollmentReceipt {
    enrolled.append(code)
    return first
  }
  func retry(code: String) throws -> RetainedRetry { throw RetainedSessionError.invalidArgument }
  func status() throws -> RetainedStatus {
    guard !statuses.isEmpty else { throw RetainedSessionError.closed }
    return statuses.removeFirst()
  }
  func refresh() -> RetainedRefresh {
    RetainedRefresh(
      initial: statusOf(receipt(.active, receiver: "r1")), read: nil, recheck: nil,
      selectionFailure: nil)
  }
  func cataloguePage(after: RetainedEntryKey?, maximum: UInt32) -> RetainedCataloguePage? {
    pages.isEmpty ? nil : pages.removeFirst()
  }
  func transcript(conversation: String, revision: UUID) throws -> RetainedTranscript {
    guard let transcriptView else { throw RetainedSessionError.invalidArgument }
    return transcriptView
  }
  func purgeReceipt(receiver: String) -> RetainedPurge? { nil }
  func close() { closes += 1 }
}

private struct Factory: RetainedSessionFactory {
  let session: Native
  func open(_ location: RetainedSessionLocation) -> any RetainedSession { session }
}

private struct Finder: GatewayFinding {
  let found: [FoundGateway]
  func find(within seconds: Double) -> [FoundGateway] { found }
}

private actor Store: LinkedDesktopStoring {
  var desktop: LinkedDesktop?
  func load() -> LinkedDesktop? { desktop }
  func save(_ desktop: LinkedDesktop) { self.desktop = desktop }
  func remove() { desktop = nil }
}

private actor Locations: LinkedDesktopLocating {
  var prepared: [String] = []
  var discarded: [UUID] = []
  func prepare(id: UUID, address: String) -> RetainedSessionLocation {
    prepared.append(address)
    return RetainedSessionLocation(root: "/root", directory: "d", address: address)
  }
  func discard(id: UUID) { discarded.append(id) }
}

private actor Heard {
  var phases: [DesktopLinkPhase] = []
  func add(_ phase: DesktopLinkPhase) { phases.append(phase) }
}

private func linking(
  _ native: Native, store: Store = Store(), locations: Locations = Locations(),
  approvalSeconds: Double = 900
) -> DesktopLinking {
  DesktopLinking(
    finder: Finder(found: [mac]), store: store, locations: locations,
    sessions: Factory(session: native), pause: { _ in }, now: { 1_000 },
    approvalSeconds: approvalSeconds)
}

@Test func pairingWaitsForApprovalThenKeepsTheDesktop() async throws {
  let native = Native(
    first: receipt(.claimed),
    then: [
      statusOf(receipt(.claimed)), statusOf(receipt(.approved)),
      statusOf(receipt(.active, receiver: "r1")),
    ])
  let store = Store()
  let locations = Locations()
  let heard = Heard()
  let desktop = try await linking(native, store: store, locations: locations)
    .link(code: "abcd2345", with: mac) { await heard.add($0) }
  #expect(await native.enrolled == ["ABCD-2345"])
  #expect(desktop.receiver == "r1")
  #expect(desktop.address == mac.address && desktop.name == "Studio")
  #expect(await store.desktop == desktop)
  #expect(await heard.phases == [.approving(mac)])
  #expect(await locations.prepared == [mac.address])
  #expect(await locations.discarded.isEmpty)
  #expect(await native.closes == 1)
}

@Test func aDeniedPhoneIsToldAndKeepsNothing() async throws {
  let native = Native(
    first: receipt(.claimed), then: [statusOf(receipt(.terminal, cause: .denied))])
  let store = Store()
  let locations = Locations()
  await #expect(throws: DesktopLinkFailure.denied) {
    try await linking(native, store: store, locations: locations).link(code: "ABCD-2345", with: mac)
  }
  #expect(await store.desktop == nil)
  #expect(await locations.discarded.count == 1)
  #expect(await native.closes == 1)
}

@Test func aWrongCodeIsSaidAsOne() async throws {
  let wrong = Native(first: receipt(.unclaimed, attempt: .failed, failure: .invalidProof))
  await #expect(throws: DesktopLinkFailure.wrongCode) {
    try await linking(wrong).link(code: "ABCD-2345", with: mac)
  }
  // Not a code at all: nothing is opened.
  let untouched = Native(first: receipt(.claimed))
  await #expect(throws: DesktopLinkFailure.wrongCode) {
    try await linking(untouched).link(code: "ABCD-234O", with: mac)
  }
  #expect(await untouched.enrolled.isEmpty)
}

@Test func theDesktopSaysWhenTheCodeExpired() async throws {
  let native = Native(
    first: receipt(.claimed), then: [statusOf(receipt(.terminal, cause: .expired))])
  await #expect(throws: DesktopLinkFailure.expired) {
    try await linking(native).link(code: "ABCD-2345", with: mac)
  }
}

@Test func aPhoneClockAheadOfTheDesktopDoesNotEndPairing() async throws {
  // The code's expiry (500) is already past by this phone's clock (1 000).
  let native = Native(
    first: receipt(.claimed, expiry: 500),
    then: [statusOf(receipt(.active, receiver: "r1", expiry: 500))])
  let desktop = try await linking(native).link(code: "ABCD-2345", with: mac)
  #expect(desktop.receiver == "r1")
}

@Test func waitingTooLongForTheOwnerStops() async throws {
  let native = Native(first: receipt(.approved))
  let locations = Locations()
  await #expect(throws: DesktopLinkFailure.expired) {
    try await linking(native, locations: locations, approvalSeconds: 0)
      .link(code: "ABCD-2345", with: mac)
  }
  #expect(await native.closes == 1)
  #expect(await locations.discarded.count == 1)
}

@Test func anUnavailableVerifierIsNotAWrongCode() async throws {
  let native = Native(first: receipt(.unclaimed, attempt: .failed, failure: .verifierUnavailable))
  await #expect(throws: DesktopLinkFailure.unreachable) {
    try await linking(native).link(code: "ABCD-2345", with: mac)
  }
}

@Test func pairingAgainForgetsThePreviousDesktop() async throws {
  let old = LinkedDesktop(
    id: UUID(), name: "Old", gateway: "gw-0", address: mac.address, receiver: "r0",
    linkedAtMs: 1)
  let store = Store()
  await store.save(old)
  let locations = Locations()
  let native = Native(first: receipt(.active, receiver: "r1"))
  let desktop = try await linking(native, store: store, locations: locations)
    .link(code: "ABCD-2345", with: mac)
  #expect(await store.desktop == desktop)
  #expect(await locations.discarded == [old.id])
}

@Test func aForgottenDesktopIsNotReadAgain() async throws {
  let desktop = LinkedDesktop(
    id: UUID(), name: "Studio", gateway: "gw-1", address: mac.address, receiver: "r1",
    linkedAtMs: 1)
  let store = Store()
  await store.save(desktop)
  let locations = Locations()
  let native = Native(first: receipt(.claimed))
  let linker = linking(native, store: store, locations: locations)
  try await linker.unlink()
  #expect(await store.desktop == nil)
  #expect(await locations.discarded == [desktop.id])
  await #expect(throws: DesktopLinkFailure.self) { try await linker.chats(of: desktop) }
  #expect(await locations.prepared.isEmpty)
}

@Test func sharedChatsAreReadNewestFirstWithoutDeletedOrArchived() async throws {
  let native = Native(first: receipt(.claimed))
  let scope = RetainedScope(
    accessEpoch: "1", incarnation: "i", origin: "o", receiver: "r1", schema: "s", stream: "t")
  func entry(_ id: String, at: UInt64, deleted: Bool = false, archived: Bool = false)
    -> RetainedCatalogueEntry
  {
    RetainedCatalogueEntry(
      agent: nil, archived: archived, createdAtMs: at, deleted: deleted,
      key: RetainedEntryKey(creation: at, id: id), model: nil, preview: "p", revision: 1,
      title: id, updatedAtMs: at)
  }
  let next = RetainedEntryKey(creation: 3, id: "c")
  await native.setPages([
    RetainedCataloguePage(
      activeBoundary: nil, activeCursor: nil, completed: 1,
      entries: [entry("a", at: 1), entry("gone", at: 9, deleted: true)], generation: 1,
      next: next, scope: scope),
    RetainedCataloguePage(
      activeBoundary: nil, activeCursor: nil, completed: 2,
      entries: [entry("c", at: 3), entry("old", at: 8, archived: true)], generation: 1,
      next: nil, scope: scope),
  ])
  let desktop = LinkedDesktop(
    id: UUID(), name: "Studio", gateway: "gw-1", address: mac.address, receiver: "r1",
    linkedAtMs: 1)
  let chats = try await linking(native).chats(of: desktop)
  #expect(chats.map(\.id) == ["c", "a"])
}

@MainActor @Test func theViewModelPicksTheOnlyMacAndSaysFailuresPlainly() async throws {
  #expect(DesktopLinkViewModel.sentence(.noDesktop).contains("Native linking"))
  #expect(!DesktopLinkViewModel.sentence(.other("wire")).contains("wire"))
}
