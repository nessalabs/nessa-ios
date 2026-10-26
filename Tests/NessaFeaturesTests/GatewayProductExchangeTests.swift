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
  private var releaseConfirmed: Bool
  private let closeFailure: (any Error)?
  private var readyCalls = 0
  init(ready: Data = productReady(), listResponse: Data? = nil,
    releaseConfirmed: Bool = true, closeFailure: (any Error)? = nil) {
    readyBytes = ready
    self.listResponse = listResponse
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
