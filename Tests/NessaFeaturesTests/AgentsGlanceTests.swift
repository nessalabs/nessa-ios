import Foundation
import Testing

@testable import NessaFeatures

@Suite struct AgentsGlanceTests {
  private func chat(_ id: String, at time: Double, running: Bool = false) -> NessaConversation {
    NessaConversation(
      conversationId: id, title: id, preview: nil, updatedAtMs: time, running: running)
  }

  @Test func eachChatLandsInOneGroupNewestFirst() {
    let glance = AgentsGlance(
      conversations: [
        chat("old", at: 1), chat("asks", at: 2, running: true), chat("busy", at: 3, running: true),
        chat("done", at: 4), chat("busier", at: 5, running: true),
      ],
      waiting: ["asks"], unread: ["done", "old"])
    #expect(glance.ids(.needsYou) == ["asks"])
    #expect(glance.ids(.working) == ["busier", "busy"])
    #expect(glance.ids(.finished) == ["done", "old"])
    #expect(glance.ids(.earlier).isEmpty)
  }

  @Test func aChatNothingWaitsOnOrWorksInIsEarlier() {
    let glance = AgentsGlance(conversations: [chat("a", at: 1)], waiting: [], unread: [])
    #expect(glance.ids(.earlier) == ["a"])
  }
}

@Test @MainActor func answeringAWaitingReviewTakesTheChatOutOfNeedsYou() async throws {
  let model = MessagesViewModel(
    service: MessagingService(repository: MockRepository()), credentials: InMemoryCredentialStore(),
    preferences: InMemoryChatPreferences())
  await model.connect(address: "mock://one", credential: "", instance: "phone")
  let id = "00000000-0000-4000-8000-000000000002"
  await model.refresh(id)
  #expect(model.agentsGlance.ids(.needsYou) == [id])
  let permission = try #require(model.views[id]?.permissions.first)
  let allow = try #require(permission.options.first { $0.effect == "allow" })
  await model.answer(permission, option: allow, in: id)
  #expect(model.agentsGlance.ids(.needsYou).isEmpty)
  #expect(model.views[id]?.permissions.isEmpty == true)
}

private func eventually(_ predicate: @MainActor () async -> Bool) async throws {
  for _ in 0..<500 {
    if await predicate() { return }
    try await Task.sleep(for: .milliseconds(2))
  }
  throw NessaGatewayError.timeout
}

@Test @MainActor func anAnnouncedReviewShowsInNeedsYouWithoutTheChatBeingOpened() async throws {
  let repository = MockRepository()
  let model = MessagesViewModel(
    service: MessagingService(repository: repository), credentials: InMemoryCredentialStore(),
    preferences: InMemoryChatPreferences())
  await model.connect(address: "mock://one", credential: "", instance: "phone")
  let id = "00000000-0000-4000-8000-000000000002"
  model.unreadChats = [id]
  let watching = Task { await model.watchReviews() }
  defer { watching.cancel() }
  try await eventually { model.agentsGlance.ids(.needsYou) == [id] }
  // Read so its card can show what it asks, but still unread: the person has not opened it.
  try await eventually { model.views[id]?.permissions.isEmpty == false }
  #expect(model.unreadChats.contains(id))
}

@Test @MainActor func aReviewAnsweredElsewhereLeavesNeedsYouThoughItsReadViewStillHoldsIt()
  async throws
{
  let repository = MockRepository()
  let model = MessagesViewModel(
    service: MessagingService(repository: repository), credentials: InMemoryCredentialStore(),
    preferences: InMemoryChatPreferences())
  await model.connect(address: "mock://one", credential: "", instance: "phone")
  let id = "00000000-0000-4000-8000-000000000002"
  await model.refresh(id)
  let watching = Task { await model.watchReviews() }
  defer { watching.cancel() }
  try await eventually { model.agentsGlance.ids(.needsYou) == [id] }
  let permission = try #require(model.views[id]?.permissions.first)
  let allow = try #require(permission.options.first { $0.effect == "allow" })
  // Another device answers it; this phone's read view is now out of date.
  try await repository.answer(permission, option: allow, conversationID: id)
  try await eventually { model.agentsGlance.ids(.needsYou).isEmpty }
  // The chat was read again quietly, so its view no longer shows the answered review.
  #expect(model.views[id]?.permissions.isEmpty == true)
}

/// The development fixture, with announcements the test sends and reads it counts.
private actor ScriptedReviews: MessagingRepository, ReviewNoticeSource {
  let base = MockRepository()
  private(set) var reads = 0
  /// A second review the fixture chat's view holds, newer than its own.
  private var extra: NessaPermission?
  func holdAnother(_ permission: NessaPermission) { extra = permission }
  private var listener: AsyncStream<WaitingReviews>.Continuation?
  func announce(_ reviews: [WaitingReviews.Review]) {
    listener?.yield(WaitingReviews(reviews: reviews))
  }
  var listening: Bool { listener != nil }
  func waitingReviews() -> AsyncStream<WaitingReviews> {
    let (stream, continuation) = AsyncStream<WaitingReviews>.makeStream()
    listener = continuation
    return stream
  }
  func connect(address: String, credential: String, instance: String) async {
    await base.connect(address: address, credential: credential, instance: instance)
  }
  func list() async throws -> NessaConversationList { try await base.list() }
  func listArchived() async throws -> NessaConversationList { try await base.listArchived() }
  func setArchived(_ archived: Bool, conversationID: String) async throws {
    try await base.setArchived(archived, conversationID: conversationID)
  }
  func read(_ id: String) async throws -> NessaConversationView {
    reads += 1
    let view = try await base.read(id)
    guard let extra, !view.permissions.isEmpty else { return view }
    return NessaConversationView(
      conversationId: view.conversationId, messages: view.messages,
      permissions: view.permissions + [extra], truncated: view.truncated,
      interactionViewError: view.interactionViewError, runtime: view.runtime)
  }
  func create(agent: String?, model: String?) async throws -> String {
    try await base.create(agent: agent, model: model)
  }
  func send(_ text: String, attachments: [DraftAttachment], conversationID: String) async throws
    -> String
  { try await base.send(text, attachments: attachments, conversationID: conversationID) }
  func answer(_ permission: NessaPermission, option: NessaPermission.Option, conversationID: String)
    async throws
  { try await base.answer(permission, option: option, conversationID: conversationID) }
  func delete(_ conversationID: String) async throws { try await base.delete(conversationID) }
  func imageData(for attachment: NessaImageAttachment) async throws -> Data? {
    try await base.imageData(for: attachment)
  }
  func disconnect() async { await base.disconnect() }
}

@Test @MainActor func aReviewTheAnnouncementLeavesOutStillWaitsAndIsReadForOnce() async throws {
  // The gateway names a bounded set and drops the oldest, so a review a read view holds can
  // still wait though no announcement names it.
  let repository = ScriptedReviews()
  let model = MessagesViewModel(
    service: MessagingService(repository: repository), credentials: InMemoryCredentialStore(),
    preferences: InMemoryChatPreferences())
  await model.connect(address: "mock://one", credential: "", instance: "phone")
  let id = "00000000-0000-4000-8000-000000000002"
  await model.refresh(id)
  let readsBefore = await repository.reads
  let watching = Task { await model.watchReviews() }
  defer { watching.cancel() }
  try await eventually { await repository.listening }
  await repository.announce([])
  try await eventually { await repository.reads == readsBefore + 1 }
  #expect(model.agentsGlance.ids(.needsYou) == [id])
  // Announced again without it: that chat was already read for this review.
  await repository.announce([])
  try await Task.sleep(for: .milliseconds(50))
  #expect(await repository.reads == readsBefore + 1)
  #expect(model.agentsGlance.ids(.needsYou) == [id])
}

@Test @MainActor func theAgentsCardAsksAboutTheReviewTheGatewayAnnounced() async throws {
  let repository = ScriptedReviews()
  let model = MessagesViewModel(
    service: MessagingService(repository: repository), credentials: InMemoryCredentialStore(),
    preferences: InMemoryChatPreferences())
  await model.connect(address: "mock://one", credential: "", instance: "phone")
  let id = "00000000-0000-4000-8000-000000000002"
  let newer = NessaPermission(
    executionId: "\(id)-8", permissionId: "newer", title: "Nessa wants to edit a file",
    toolName: "edit", argumentsJson: "{}",
    options: [NessaPermission.Option(id: "allow_once", label: "Allow once", effect: "allow")])
  await repository.holdAnother(newer)
  await model.refresh(id)
  let oldest = try #require(model.views[id]?.permissions.first)
  #expect(model.views[id]?.permissions.count == 2)
  // With nothing announced, the oldest the view holds.
  #expect(model.waitingPermission(in: id) == oldest)
  let watching = Task { await model.watchReviews() }
  defer { watching.cancel() }
  try await eventually { await repository.listening }
  // The older one was answered elsewhere and the view here is behind: the announced one.
  await repository.announce([
    .init(
      conversationId: id, executionId: newer.executionId, permissionId: newer.permissionId,
      tool: newer.toolName, title: nil)
  ])
  try await eventually { model.waitingReviews?.reviews.count == 1 }
  #expect(model.waitingPermission(in: id) == newer)
  #expect(model.waitingPermission(in: "00000000-0000-4000-8000-000000000009") == nil)
}
