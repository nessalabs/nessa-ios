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
  var closeFails = false
  /// While set, a catalogue read waits until `release()`.
  var holding = false
  var held: CheckedContinuation<Void, Never>?
  init(first: RetainedEnrollmentReceipt, then statuses: [RetainedStatus] = []) {
    self.first = first
    self.statuses = statuses
  }
  func setPages(_ pages: [RetainedCataloguePage?]) { self.pages = pages }
  func setTranscript(_ value: RetainedTranscript) { transcriptView = value }
  func failClose() { closeFails = true }
  func hold() { holding = true }
  func release() {
    holding = false
    held?.resume()
    held = nil
  }
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
  func cataloguePage(after: RetainedEntryKey?, maximum: UInt32) async -> RetainedCataloguePage? {
    if holding { await withCheckedContinuation { held = $0 } }
    return pages.isEmpty ? nil : pages.removeFirst()
  }
  func transcript(conversation: String, revision: UUID) throws -> RetainedTranscript {
    guard let transcriptView else { throw RetainedSessionError.invalidArgument }
    return transcriptView
  }
  func purgeReceipt(receiver: String) -> RetainedPurge? { nil }
  func close() throws {
    closes += 1
    if closeFails { throw RetainedSessionError.closed }
  }
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
  func remove(_ id: UUID) { if desktop?.id == id { desktop = nil } }
  func remember(tunnel: String, for id: UUID) {
    if let kept = desktop, kept.id == id { desktop = kept.reaching(tunnel) }
  }
}

private struct BrokenStore: LinkedDesktopStoring {
  func load() throws -> LinkedDesktop? { nil }
  func save(_ desktop: LinkedDesktop) throws { throw DesktopLinkFailure.storage }
  func remove(_ id: UUID) {}
  func remember(tunnel: String, for id: UUID) throws { throw DesktopLinkFailure.storage }
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
  _ native: Native, store: any LinkedDesktopStoring = Store(), locations: Locations = Locations(),
  approvalSeconds: Double = 900
) -> DesktopLinking {
  DesktopLinking(
    finder: Finder(found: [mac]), store: store, locations: locations,
    sessions: Factory(session: native), pause: { _ in }, now: { 1_000 }, elapsed: { 1_000 },
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
  let linker = linking(native, store: store, locations: locations)
  let desktop = try await linker.link(code: "ABCD-2345", with: mac)
  #expect(await store.desktop == desktop)
  await linker.settled()
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
  await #expect(throws: DesktopLinkFailure.other("forgotten")) {
    try await linker.chats(of: desktop)
  }
  #expect(await locations.prepared.isEmpty)
}

@Test func forgettingWaitsForAReadUnderWay() async throws {
  let desktop = LinkedDesktop(
    id: UUID(), name: "Studio", gateway: "gw-1", address: mac.address, receiver: "r1",
    linkedAtMs: 1)
  let store = Store()
  await store.save(desktop)
  let locations = Locations()
  let native = Native(first: receipt(.claimed))
  await native.hold()
  let linker = linking(native, store: store, locations: locations)
  let reading = Task { try await linker.chats(of: desktop) }
  while await native.held == nil { await Task.yield() }
  let forgetting = Task { try await linker.unlink() }
  while await store.desktop != nil { await Task.yield() }
  for _ in 0..<100 { await Task.yield() }
  #expect(await locations.discarded.isEmpty)
  await native.release()
  try await forgetting.value
  _ = try? await reading.value
  #expect(await locations.discarded == [desktop.id])
}

@Test func aReadThatWontCloseKeepsItsDirectory() async throws {
  let desktop = LinkedDesktop(
    id: UUID(), name: "Studio", gateway: "gw-1", address: mac.address, receiver: "r1",
    linkedAtMs: 1)
  let store = Store()
  await store.save(desktop)
  let locations = Locations()
  let native = Native(first: receipt(.claimed))
  await native.failClose()
  let linker = linking(native, store: store, locations: locations)
  _ = try await linker.chats(of: desktop)
  try await linker.unlink()
  #expect(await store.desktop == nil)
  #expect(await locations.discarded.isEmpty)
}

@Test func aPairingThatWontCloseKeepsItsDirectory() async throws {
  let native = Native(first: receipt(.active, receiver: "r1"))
  await native.failClose()
  let store = Store()
  let locations = Locations()
  let linker = linking(native, store: store, locations: locations)
  let desktop = try await linker.link(code: "ABCD-2345", with: mac)
  #expect(await store.desktop == desktop)
  try await linker.unlink()
  #expect(await locations.discarded.isEmpty)
}

@Test func anAbandonedPairingThatWontCloseKeepsItsDirectory() async throws {
  let native = Native(first: receipt(.approved))
  await native.failClose()
  let locations = Locations()
  await #expect(throws: DesktopLinkFailure.expired) {
    try await linking(native, locations: locations, approvalSeconds: 0)
      .link(code: "ABCD-2345", with: mac)
  }
  #expect(await native.closes == 1)
  #expect(await locations.discarded.isEmpty)
}

@Test func pairingDoesNotWaitForAReadOfThePreviousDesktop() async throws {
  let old = LinkedDesktop(
    id: UUID(), name: "Old", gateway: "gw-0", address: mac.address, receiver: "r1",
    linkedAtMs: 1)
  let store = Store()
  await store.save(old)
  let locations = Locations()
  // Pairing never reads the catalogue, so only the old desktop's read is held.
  let native = Native(first: receipt(.active, receiver: "r1"))
  await native.hold()
  let linker = linking(native, store: store, locations: locations)
  let reading = Task { try await linker.chats(of: old) }
  while await native.held == nil { await Task.yield() }
  let desktop = try await linker.link(code: "ABCD-2345", with: mac)
  #expect(await store.desktop == desktop)
  #expect(await locations.discarded.isEmpty)
  await native.release()
  _ = try? await reading.value
  await linker.settled()
  #expect(await locations.discarded == [old.id])
}

@Test func aPairingThatCannotBeSavedOrClosedKeepsItsDirectory() async throws {
  let native = Native(first: receipt(.active, receiver: "r1"))
  await native.failClose()
  let locations = Locations()
  await #expect(throws: DesktopLinkFailure.storage) {
    try await linking(native, store: BrokenStore(), locations: locations)
      .link(code: "ABCD-2345", with: mac)
  }
  #expect(await native.closes == 1)
  #expect(await locations.discarded.isEmpty)
}

@Test func theFileStoreForgetsOnlyTheDesktopItWasAskedTo() async throws {
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let store = LinkedDesktopFileStore(root: root)
  let paired = LinkedDesktop(
    id: UUID(), name: "New", gateway: "gw-2", address: mac.address, receiver: "r2",
    linkedAtMs: 2)
  try await store.save(paired)
  try await store.remove(UUID())
  #expect(try await store.load() == paired)
  try await store.remove(paired.id)
  #expect(try await store.load() == nil)
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

/// A product exchange that only records how it was closed.
private final class Exchange: GatewayProductExchange, @unchecked Sendable {
  let released: Bool
  private let lock = NSLock()
  private var closes = 0
  init(released: Bool = true) { self.released = released }
  var closed: Int { lock.withLock { closes } }
  func ready() async throws -> Data { Data() }
  func request(method: String, parameters: Data) async throws -> Data { Data() }
  func events() async throws -> [Data] { [] }
  func requestClose() {}
  func close() async -> GatewayProductCloseObservation {
    lock.withLock { closes += 1 }
    return .init(released: released, failure: nil)
  }
}

private struct Products: LinkedProductOpening {
  let exchange: Exchange
  func open(_ desktop: LinkedDesktop, instance: String) async throws
    -> any GatewayProductExchange
  { exchange }
}

/// The product session to the Mac holds its directory like a read: forgetting
/// the Mac waits until the session closed, and one that did not let go keeps
/// the directory. A forgotten Mac opens no new session.
@Test func forgettingWaitsForTheProductSession() async throws {
  for released in [true, false] {
    let desktop = LinkedDesktop(
      id: UUID(), name: "Studio", gateway: "gw-1", address: mac.address, receiver: "r1",
      linkedAtMs: 1)
    let store = Store()
    await store.save(desktop)
    let locations = Locations()
    let linker = linking(Native(first: receipt(.claimed)), store: store, locations: locations)
    let inner = Exchange(released: released)
    let product = try await linker.openProduct(
      desktop, instance: "phone", through: Products(exchange: inner))
    let forgetting = Task { try await linker.unlink() }
    while await store.desktop != nil { await Task.yield() }
    for _ in 0..<100 { await Task.yield() }
    #expect(await locations.discarded.isEmpty)
    _ = await product.close()
    _ = await product.close()
    try await forgetting.value
    #expect(inner.closed == 2)
    #expect(await locations.discarded == (released ? [desktop.id] : []))
    await #expect(throws: DesktopLinkFailure.other("forgotten")) {
      try await linker.openProduct(desktop, instance: "phone", through: Products(exchange: inner))
    }
  }
}

/// A product exchange whose desktop answers `server.reach` with `tunnel`.
private final class Reaching: GatewayProductExchange, @unchecked Sendable {
  let tunnel: String?
  private let lock = NSLock()
  private var asked: [String] = []
  init(tunnel: String?) { self.tunnel = tunnel }
  var methods: [String] { lock.withLock { asked } }
  func ready() async throws -> Data { Data("{}".utf8) }
  func request(method: String, parameters: Data) async throws -> Data {
    lock.withLock { asked.append(method) }
    let payload: [String: Any] = ["tunnel": tunnel ?? NSNull()]
    return try JSONSerialization.data(withJSONObject: ["id": "1", "ok": true, "payload": payload])
  }
  func events() async throws -> [Data] { [] }
  func requestClose() {}
  func close() async -> GatewayProductCloseObservation { .init(released: true, failure: nil) }
}

/// Opens `exchange` and records the tunnel each opening was asked to dial.
private actor Dialed {
  var tunnels: [String?] = []
  func add(_ tunnel: String?) { tunnels.append(tunnel) }
}
private struct DialingProducts: LinkedProductOpening {
  let exchange: Reaching
  let dialed: Dialed
  func open(_ desktop: LinkedDesktop, instance: String) async throws
    -> any GatewayProductExchange
  {
    await dialed.add(desktop.tunnel)
    return exchange
  }
}

/// Once a product session is ready the phone asks where else its Mac can be
/// reached and keeps the answer with the Mac, so the next opening dials it
/// even from a copy of the record made before. No tunnel in an answer, or an
/// address that is not an `https` origin, keeps the last one.
@Test func aReadyProductSessionLearnsTheMacsTunnelForTheNextDial() async throws {
  let desktop = LinkedDesktop(
    id: UUID(), name: "Studio", gateway: "gw-1", address: mac.address, receiver: "r1",
    linkedAtMs: 1)
  let store = Store()
  await store.save(desktop)
  let linker = linking(Native(first: receipt(.claimed)), store: store)
  let dialed = Dialed()
  let origin = "https://gateway.example.com"
  let answers: [String?] = [origin, nil, "http://gateway.example.com", "https://a.example/path"]
  for answer in answers {
    let reaching = Reaching(tunnel: answer)
    let product = try await linker.openProduct(
      desktop, instance: "phone", through: DialingProducts(exchange: reaching, dialed: dialed))
    _ = try await product.ready()
    while reaching.methods.isEmpty { await Task.yield() }
    for _ in 0..<100 { await Task.yield() }
    #expect(reaching.methods == ["server.reach"])
    #expect(await store.desktop?.tunnel == origin)
    _ = await product.close()
  }
  #expect(await dialed.tunnels == [nil, origin, origin, origin])
}

/// Keeping a tunnel never brings back a Mac forgotten, or overwrites one
/// paired, while the answer was on its way.
@Test func aLateTunnelAnswerKeepsOnlyTheMacItWasFor() async throws {
  let desktop = LinkedDesktop(
    id: UUID(), name: "Studio", gateway: "gw-1", address: mac.address, receiver: "r1",
    linkedAtMs: 1)
  let other = LinkedDesktop(
    id: UUID(), name: "Laptop", gateway: "gw-2", address: mac.address, receiver: "r2",
    linkedAtMs: 2)
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: root) }
  let store = LinkedDesktopFileStore(root: root)
  try await store.remember(tunnel: "https://gateway.example.com", for: desktop.id)
  #expect(try await store.load() == nil)
  try await store.save(other)
  try await store.remember(tunnel: "https://gateway.example.com", for: desktop.id)
  #expect(try await store.load() == other)
  try await store.remember(tunnel: "https://gateway.example.com", for: other.id)
  #expect(try await store.load() == other.reaching("https://gateway.example.com"))
}
