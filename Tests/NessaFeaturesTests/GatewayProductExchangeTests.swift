import CryptoKit
import Foundation
import Testing

@testable import NessaFeatures

private enum ProductFixtureFailure: Error, Equatable { case notDispatched, uncertain }

/// Application port fixture. These tests verify repository scheduling; actual
/// native ticket, TLS and physical-release tests belong to the native package.
private actor ProductExchangeFixture: GatewayProductExchange {
  private var calls: [(String, Data)] = []
  private var registrations: [CheckedContinuation<Data, Error>] = []
  private var eventWaiter: CheckedContinuation<[Data], Error>?
  private var queued: [[Data]] = []
  private var stopped = false
  private var closes = 0
  private var creation: CheckedContinuation<Data, Error>?
  private let readyBytes: Data
  private let listResponse: Data?
  /// `channel.list` answers, one per call, in order.
  private var channelPages: [Data]
  private var releaseConfirmed: Bool
  private let closeFailure: (any Error)?
  private var readyCalls = 0
  /// Answers for any other method, one per call, in order.
  private var scripted: [String: [Data]]
  init(ready: Data = productReady(), listResponse: Data? = nil, channelPages: [Data] = [],
    scripted: [String: [Data]] = [:],
    releaseConfirmed: Bool = true, closeFailure: (any Error)? = nil) {
    self.scripted = scripted
    readyBytes = ready
    self.listResponse = listResponse
    self.channelPages = channelPages
    self.releaseConfirmed = releaseConfirmed
    self.closeFailure = closeFailure
  }
  func ready() -> Data { readyCalls += 1; return readyBytes }
  func request(method: String, parameters: Data) async throws -> Data {
    calls.append((method, parameters))
    if stopped { throw ProductFixtureFailure.notDispatched }
    if method == "conversation.subscribe" || method == "conversation.subscribeList" {
      return try await withCheckedThrowingContinuation { registrations.append($0) }
    }
    if method == "conversation.list" {
      if let listResponse { return listResponse }
      return Data(#"{"type":"res","id":"9007199254740993","ok":true,"payload":{"conversations":[],"complete":true}}"#.utf8)
    }
    if method == "channel.list", !channelPages.isEmpty { return channelPages.removeFirst() }
    if var answers = scripted[method], !answers.isEmpty {
      let answer = answers.removeFirst()
      scripted[method] = answers
      return answer
    }
    if method == "conversation.create" {
      return try await withCheckedThrowingContinuation { creation = $0 }
    }
    return Data(#"{"type":"res","id":"18446744073709551614","ok":true,"payload":{}}"#.utf8)
  }
  func events() async throws -> [Data] {
    if stopped { throw ProductFixtureFailure.uncertain }
    if !queued.isEmpty { return queued.removeFirst() }
    return try await withCheckedThrowingContinuation { eventWaiter = $0 }
  }
  nonisolated func requestClose() { Task { await self.stop() } }
  func close() -> GatewayProductCloseObservation {
    stop(); closes += 1
    return .init(released: releaseConfirmed, failure: closeFailure)
  }
  func stop() {
    stopped = true
    eventWaiter?.resume(throwing: ProductFixtureFailure.uncertain)
    eventWaiter = nil
    for waiter in registrations { waiter.resume(throwing: ProductFixtureFailure.uncertain) }
    registrations.removeAll()
  }
  func callCount(_ method: String) -> Int { calls.filter { $0.0 == method }.count }
  func parameters(_ method: String) -> Data? { calls.first { $0.0 == method }?.1 }
  func allParameters(_ method: String) -> [Data] { calls.filter { $0.0 == method }.map(\.1) }
  func pendingRegistrations() -> Int { registrations.count }
  func waitingForEvents() -> Bool { eventWaiter != nil }
  func closeCount() -> Int { closes }
  func readyCount() -> Int { readyCalls }
  func confirmRelease() { releaseConfirmed = true }
  func creationAccepted() -> Bool { creation != nil }
  func finishCreation(_ id: String) {
    creation?.resume(returning: Data("{\"type\":\"res\",\"id\":\"18446744073709551614\",\"ok\":true,\"payload\":{\"conversationId\":\"\(id)\"}}".utf8))
    creation = nil
  }
  func finishRegistration(_ result: Result<Data, Error>) {
    registrations.removeFirst().resume(with: result)
  }
  func emit(_ bytes: Data) {
    if let waiter = eventWaiter {
      eventWaiter = nil
      waiter.resume(returning: [bytes])
    } else { queued.append([bytes]) }
  }
}

private func productReady() -> Data {
  Data(#"{"version":1,"gatewayId":"gateway","principalId":"device","organizationId":"org","membershipId":"member","credentialId":"issued","audienceId":"phone","expiresAt":null,"grants":[],"methods":["conversation.list","conversation.subscribeList","conversation.subscribe","conversation.unsubscribe"]}"#.utf8)
}
private func registered(_ id: String) -> Data {
  Data("{\"type\":\"res\",\"id\":\"18446744073709551614\",\"ok\":true,\"payload\":{\"subscriptionId\":\"\(id)\"}}".utf8)
}
private func listed(_ id: String) -> Data {
  Data("{\"type\":\"event\",\"event\":\"conversation.listed\",\"payload\":{\"subscriptionId\":\"\(id)\",\"list\":{\"conversations\":[],\"complete\":true}}}".utf8)
}
private final class BatchObservation: @unchecked Sendable {
  private let lock = NSLock()
  private var value = false
  func observe() { lock.withLock { value = true } }
  func observed() -> Bool { lock.withLock { value } }
}
private func eventually(_ predicate: @Sendable () async -> Bool) async throws {
  for _ in 0..<500 {
    if await predicate() { return }
    try await Task.sleep(for: .milliseconds(2))
  }
  throw NessaGatewayError.timeout
}
private func connect(_ client: NessaGatewayClient, _ exchange: ProductExchangeFixture) async throws
  -> GatewayConnectionLease
{
  try await client.connectProduct(
    exchange, uploads: "ws://127.0.0.1:19743/session",
    scope: .init(address: "native-original", credential: "public-device-key", instance: "phone"))
}

@Test func productReadyUsesActualDelegatedIdentityAndEventWaitDoesNotBlockRequest() async throws {
  let exchange = ProductExchangeFixture()
  let client = NessaGatewayClient()
  let lease = try await connect(client, exchange)
  #expect(try await client.authenticatedSession(for: lease).snapshot.identity.credentialID == "issued")
  try await eventually { await exchange.waitingForEvents() }
  #expect(try await client.list().complete)
  #expect(await exchange.callCount("conversation.list") == 1)
  let params = try #require(await exchange.parameters("conversation.list"))
  let object = try #require(JSONSerialization.jsonObject(with: params) as? [String: Any])
  #expect(object["id"] == nil && object["type"] == nil)
  await client.disconnect()
  try await eventually { await exchange.closeCount() > 0 }
  await #expect(throws: NessaGatewayError.self) { try await client.authenticatedSession(for: lease) }
}

@Test func productRejectionRetainsCanonicalDetailsAndUsesOnlyPublishedCode() async throws {
  let response = Data(#"{"type":"res","id":"18446744073709551614","ok":false,"error":{"code":"model_unavailable","message":"Timed out; please retry","details":null}}"#.utf8)
  let exchange = ProductExchangeFixture(listResponse: response)
  let client = NessaGatewayClient()
  _ = try await connect(client, exchange)
  do {
    _ = try await client.list()
    Issue.record("Expected model refusal")
  } catch let failure as GatewayProductRejection {
    #expect(failure.code == "model_unavailable")
    #expect(failure.diagnostic == "Timed out; please retry")
    #expect(failure.details == Data("null".utf8))
    if case .modelUnavailable = failure.behavior {} else { Issue.record("Lost refusal behavior") }
    #expect(!ConnectionRecovery.retryable(failure))
  }
  await client.disconnect()
}

@Test func productFirstBatchWaitsForRegistrationWithoutLosingFirstView() async throws {
  let exchange = ProductExchangeFixture()
  let observation = BatchObservation()
  let client = NessaGatewayClient(productBatchWaiting: { observation.observe() })
  _ = try await connect(client, exchange)
  let follow = Task { try await client.follow(nil) }
  try await eventually { await exchange.pendingRegistrations() == 1 }
  // Both native publications may be ready while Swift completion capture lags.
  await exchange.emit(listed("inbox"))
  try await eventually { observation.observed() }
  #expect(try await client.list().complete)
  await exchange.finishRegistration(.success(registered("inbox")))
  let stream = try await follow.value
  var iterator = stream.makeAsyncIterator()
  if case .list(let list) = try await iterator.next() {
    #expect(list == .init(conversations: [], complete: true))
  } else { Issue.record("Missing first inbox publication") }
  await client.disconnect()
}

@Test func productPreAdmissionRegistrationFailureWakesHeldExistingFeed() async throws {
  let exchange = ProductExchangeFixture()
  let observation = BatchObservation()
  let client = NessaGatewayClient(productBatchWaiting: { observation.observe() })
  _ = try await connect(client, exchange)
  let inbox = Task { try await client.follow(nil) }
  try await eventually { await exchange.pendingRegistrations() == 1 }
  await exchange.finishRegistration(.success(registered("inbox")))
  let stream = try await inbox.value
  let thread = Task { try await client.follow("thread") }
  try await eventually { await exchange.pendingRegistrations() == 1 }
  // A real existing feed can publish while another registration has not dispatched.
  await exchange.emit(listed("inbox"))
  try await eventually { observation.observed() }
  await exchange.finishRegistration(.failure(ProductFixtureFailure.notDispatched))
  await #expect(throws: ProductFixtureFailure.notDispatched) { try await thread.value }
  var iterator = stream.makeAsyncIterator()
  if case .list(let list) = try await iterator.next() {
    #expect(list == .init(conversations: [], complete: true))
  } else { Issue.record("Missing first inbox publication") }
  #expect(try await client.list().complete)
  await client.disconnect()
}

@Test func productDisconnectWakesHeldBatchAndCannotPublishRetiredLease() async throws {
  let exchange = ProductExchangeFixture()
  let observation = BatchObservation()
  let client = NessaGatewayClient(productBatchWaiting: { observation.observe() })
  let lease = try await connect(client, exchange)
  let follow = Task { try await client.follow(nil) }
  try await eventually { await exchange.pendingRegistrations() == 1 }
  await exchange.emit(listed("inbox"))
  try await eventually { observation.observed() }
  await client.disconnect()
  await #expect(throws: (any Error).self) { try await follow.value }
  try await eventually { await exchange.closeCount() > 0 }
  await #expect(throws: NessaGatewayError.self) { try await client.authenticatedSession(for: lease) }
  let next = ProductExchangeFixture()
  let replacement = try await connect(client, next)
  #expect(replacement != lease)
  #expect(try await client.list().complete)
  await client.disconnect()
}

@Test func productFactualCommandAcknowledgmentSurvivesLeaseRetirement() async throws {
  let exchange = ProductExchangeFixture()
  let client = NessaGatewayClient()
  let lease = try await connect(client, exchange)
  let id = UUID().uuidString.lowercased()
  let command = PreparedConversationCommand.create(.init(
    requestID: UUID().uuidString.lowercased(), conversationID: id, agent: nil, model: nil))
  let request = Task {
    try await client.dispatch(command, connection: lease,
      scope: .init(address: "native-original", credential: "public-device-key", instance: "phone"))
  }
  try await eventually { await exchange.creationAccepted() }
  // Factual native completion can precede disconnect while off-UI capture lags.
  request.cancel()
  await client.disconnect()
  await exchange.finishCreation(id)
  #expect(try await request.value == .created(id))
  await #expect(throws: NessaGatewayError.self) { try await client.authenticatedSession(for: lease) }
}

@Test(arguments: [false, true])
func productReplacementUsesReleaseFactSeparatelyFromHistoricalFault(released: Bool) async throws {
  let old = ProductExchangeFixture(releaseConfirmed: released,
    closeFailure: ProductFixtureFailure.uncertain)
  let client = NessaGatewayClient()
  _ = try await connect(client, old)
  await client.disconnect()
  let replacement = ProductExchangeFixture()
  if released {
    _ = try await connect(client, replacement)
    #expect(await replacement.readyCount() == 1)
    #expect(try await client.list().complete)
  } else {
    await #expect(throws: ProductFixtureFailure.uncertain) { try await connect(client, replacement) }
    #expect(await replacement.readyCount() == 0)
    #expect(await replacement.closeCount() == 1)
  }
  await client.disconnect()
}

@Test func productPretransferChildKeepsItsOwnUnconfirmedReleaseBarrier() async throws {
  let old = ProductExchangeFixture(releaseConfirmed: false,
    closeFailure: ProductFixtureFailure.uncertain)
  let client = NessaGatewayClient()
  _ = try await connect(client, old)
  await client.disconnect()
  let untransferred = ProductExchangeFixture(releaseConfirmed: false)
  await #expect(throws: ProductFixtureFailure.uncertain) { try await connect(client, untransferred) }
  #expect(await untransferred.readyCount() == 0)
  await old.confirmRelease()
  let blocked = ProductExchangeFixture()
  await #expect(throws: NessaGatewayError.self) { try await connect(client, blocked) }
  #expect(await blocked.readyCount() == 0)
  // The earlier source's release cannot settle the other child's actual owner.
  await untransferred.confirmRelease()
  let replacement = ProductExchangeFixture()
  _ = try await connect(client, replacement)
  #expect(await replacement.readyCount() == 1)
  #expect(try await client.list().complete)
  await client.disconnect()
}

private func channelPage(_ channels: [String], complete: Bool, cursor: String?) -> Data {
  let list = channels.map {
    "{\"channelId\":\"\($0)\",\"name\":\"\($0)\",\"folder\":\"/tmp/\($0)\","
      + "\"agent\":null,\"model\":null,\"approvalMode\":\"ask\",\"createdAtMs\":1,"
      + "\"folderMade\":false}"
  }.joined(separator: ",")
  let next = cursor.map { ",\"cursor\":\"\($0)\"" } ?? ""
  return Data(
    "{\"type\":\"res\",\"id\":\"18446744073709551614\",\"ok\":true,\"payload\":{\"channels\":[\(list)],\"complete\":\(complete)\(next)}}"
      .utf8)
}

@Test func channelPagesFollowTheCursorToTheEnd() async throws {
  let exchange = ProductExchangeFixture(channelPages: [
    channelPage(["ch_aaaaaaaaaa"], complete: false, cursor: "ch_aaaaaaaaaa"),
    channelPage(["ch_bbbbbbbbbb"], complete: true, cursor: nil),
  ])
  let client = NessaGatewayClient()
  _ = try await connect(client, exchange)
  #expect(try await client.channels().map(\.channelId) == ["ch_aaaaaaaaaa", "ch_bbbbbbbbbb"])
  #expect(await exchange.callCount("channel.list") == 2)
  await client.disconnect()
}

@Test func anUnfinishedChannelListWithNowhereToGoIsRefused() async throws {
  let exchange = ProductExchangeFixture(channelPages: [
    channelPage(["ch_aaaaaaaaaa"], complete: false, cursor: nil)
  ])
  let client = NessaGatewayClient()
  _ = try await connect(client, exchange)
  await #expect(throws: NessaGatewayError.invalidFrame) { try await client.channels() }
  await client.disconnect()
}

@Test func aChannelCursorSeenBeforeIsRefusedRatherThanFollowedForEver() async throws {
  let exchange = ProductExchangeFixture(channelPages: [
    channelPage([], complete: false, cursor: "ch_aaaaaaaaaa"),
    channelPage([], complete: false, cursor: "ch_bbbbbbbbbb"),
    channelPage([], complete: false, cursor: "ch_aaaaaaaaaa"),
  ])
  let client = NessaGatewayClient()
  _ = try await connect(client, exchange)
  await #expect(throws: NessaGatewayError.invalidFrame) { try await client.channels() }
  #expect(await exchange.callCount("channel.list") == 3)
  await client.disconnect()
}

private func reviewsWaiting(_ conversations: [String]) -> Data {
  let reviews = conversations.map {
    "{\"conversationId\":\"\($0)\",\"executionId\":\"run\",\"permissionId\":\"p\",\"tool\":\"shell\"}"
  }.joined(separator: ",")
  return Data(
    "{\"type\":\"event\",\"event\":\"permission.reviewWaiting\",\"payload\":{\"reviews\":[\(reviews)]}}"
      .utf8)
}

@Test func reviewAnnouncementsReachListenersAndTheLatestGreetsALateOne() async throws {
  let chat = "00000000-0000-4000-8000-000000000002"
  let exchange = ProductExchangeFixture()
  let client = NessaGatewayClient()
  _ = try await connect(client, exchange)
  var early = await client.waitingReviews().makeAsyncIterator()
  try await eventually { await exchange.waitingForEvents() }
  await exchange.emit(reviewsWaiting([chat]))
  #expect(await early.next()?.conversationIDs == [chat])
  // Someone listening only now still hears what waits.
  var late = await client.waitingReviews().makeAsyncIterator()
  #expect(await late.next()?.conversationIDs == [chat])
  try await eventually { await exchange.waitingForEvents() }
  await exchange.emit(reviewsWaiting([]))
  #expect(await early.next()?.reviews.isEmpty == true)
  // The connection ending ends every listener.
  await client.disconnect()
  #expect(await early.next() == nil)
}

@Test func aReviewAnnouncementOffTheGatewaysShapeEndsOnlyTheReviewFeed() async throws {
  let chat = "00000000-0000-4000-8000-000000000002"
  let exchange = ProductExchangeFixture()
  let client = NessaGatewayClient()
  _ = try await connect(client, exchange)
  var listener = await client.waitingReviews().makeAsyncIterator()
  try await eventually { await exchange.waitingForEvents() }
  await exchange.emit(reviewsWaiting(["not-a-conversation-id"]))
  #expect(await listener.next() == nil)
  // Later notices on this connection are not trusted either, and nobody new hears them.
  try await eventually { await exchange.waitingForEvents() }
  await exchange.emit(reviewsWaiting([chat]))
  try await eventually { await exchange.waitingForEvents() }
  var late = await client.waitingReviews().makeAsyncIterator()
  #expect(await late.next() == nil)
  // The connection itself stays up.
  #expect(await exchange.closeCount() == 0)
  _ = try await client.list()
  await client.disconnect()
}

private func answered(_ payload: String) -> Data {
  Data("{\"type\":\"res\",\"id\":\"18446744073709551614\",\"ok\":true,\"payload\":\(payload)}".utf8)
}
private func refusedWith(_ code: String) -> Data {
  Data("{\"type\":\"res\",\"id\":\"18446744073709551614\",\"ok\":false,\"error\":{\"code\":\"\(code)\",\"message\":\"internal words\"}}".utf8)
}
private let uploadTicket = String(repeating: "ab", count: 32)
private func ticketAnswer() -> Data {
  answered(
    "{\"requestId\":\"r\",\"state\":\"upload_required\",\"ticket\":\"\(uploadTicket)\",\"expiresAtMs\":\(Int(Date().timeIntervalSince1970 * 1000) + 60_000),\"digest\":null,\"mimeType\":null,\"size\":null}"
  )
}
private func connectLinked(_ client: NessaGatewayClient, _ exchange: ProductExchangeFixture)
  async throws
{
  _ = try await client.connectLinked(
    exchange, scope: .init(address: "native-original", credential: "public-device-key", instance: "phone"))
}
private struct WrittenPiece: Decodable {
  let ticket: String
  let offset: Int
  let data: String
  let last: Bool
}

@Test func overTheMacLinkAPhotoGoesUpInPiecesOverTheSession() async throws {
  let bytes = Data((0..<(70 * 1024)).map { UInt8($0 % 251) })
  let digest = "sha256:" + SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
  let exchange = ProductExchangeFixture(scripted: [
    "attachment.begin": [ticketAnswer()],
    "attachment.write": [
      answered(#"{"received":32768,"digest":null,"mimeType":null,"size":null}"#),
      answered(#"{"received":65536,"digest":null,"mimeType":null,"size":null}"#),
      answered("{\"received\":\(bytes.count),\"digest\":\"\(digest)\",\"mimeType\":\"image/png\",\"size\":\(bytes.count)}"),
    ],
  ])
  let client = NessaGatewayClient()
  try await connectLinked(client, exchange)
  let image = try await client.uploadPhoneImage(
    DraftAttachment(name: "photo.png", mimeType: "image/png", data: bytes),
    conversationID: "00000000-0000-4000-8000-000000000001")
  #expect(image == NessaImageAttachment(digest: digest, mimeType: "image/png", size: bytes.count))
  let pieces = try await exchange.allParameters("attachment.write").map {
    try JSONDecoder().decode(WrittenPiece.self, from: $0)
  }
  #expect(pieces.map(\.offset) == [0, 32768, 65536])
  #expect(pieces.map(\.last) == [false, false, true])
  #expect(pieces.allSatisfy { $0.ticket == uploadTicket })
  #expect(Data(pieces.compactMap { Data(base64Encoded: $0.data) }.joined()) == bytes)
  await client.disconnect()
}

@Test(arguments: [
  ("unknown_method", "Update Nessa on your Mac to send photos from your phone. Your draft has been kept."),
  ("upload_failed", "The photo didn’t finish sending. Your draft has been kept."),
  ("image_too_large", "This photo is too large to send. Try a smaller one."),
])
func aRefusedPieceIsToldInPlainWords(code: String, words: String) async throws {
  let exchange = ProductExchangeFixture(scripted: [
    "attachment.begin": [ticketAnswer()], "attachment.write": [refusedWith(code)],
  ])
  let client = NessaGatewayClient()
  try await connectLinked(client, exchange)
  do {
    _ = try await client.uploadPhoneImage(
      DraftAttachment(name: "photo.png", mimeType: "image/png", data: Data([1, 2, 3])),
      conversationID: "00000000-0000-4000-8000-000000000001")
    Issue.record("the upload should have been refused")
  } catch {
    #expect(error.localizedDescription == words)
  }
  #expect(await exchange.callCount("attachment.write") == 1)
  await client.disconnect()
}
