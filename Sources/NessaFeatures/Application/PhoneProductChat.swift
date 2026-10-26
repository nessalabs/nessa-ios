import Foundation

/// Product-socket calls the outbox does not own: image upload and Stop.
protocol PhoneProductTransport: PhoneOutboxAsking {
  func uploadPhoneImage(_ attachment: DraftAttachment, conversationID: String) async throws
    -> NessaImageAttachment
  func phoneStop(conversationID: String, requestID: String, executionID: String) async
    -> PhoneSendAnswer
  func phoneLookupStop(conversationID: String, requestID: String, executionID: String) async
    -> PhoneLookupAnswer
}

struct PhoneStopRecord: Equatable, Codable, Sendable {
  var conversationID: String
  var requestID: String
  var executionID: String
  var departed: Bool
  var outcome: PhoneSendOutcome
}

protocol PhoneStopStoring: Sendable {
  func load() async throws -> [PhoneStopRecord]
  func save(_ records: [PhoneStopRecord]) async throws
}

enum PhoneAccess {
  static let revocationCodes: Set<String> = ["forbidden", "unauthorized", "credential_revoked"]
  static func revoked(_ code: String) -> Bool { revocationCodes.contains(code) }
  static func revoked(_ error: any Error) -> Bool {
    if case .revoked = error as? NessaGatewayError { return true }
    if let rejection = error as? GatewayProductRejection { return revoked(rejection.code) }
    if let ended = error as? ConversationFeedEnded, let code = ended.code {
      return revoked(code)
    }
    return false
  }
}

/// Chat over the ordinary product socket: subscribe for the list and for replies,
/// and send text or images through the outbox.
public actor PhoneProductChat {
  private var outbox: PhoneOutbox
  private let transport: any PhoneProductTransport
  private var stops: any PhoneStopStoring
  /// When set, each `PhoneCacheScope` gets its own directory. Injected stores ignore it.
  private let root: URL?
  private var boundScope: String?
  init(
    outbox: PhoneOutbox, transport: any PhoneProductTransport, stops: any PhoneStopStoring
  ) {
    self.outbox = outbox
    self.transport = transport
    self.stops = stops
    root = nil
  }

  /// Live wiring. Records stay partitioned by the same connection scope as snapshots and commands.
  init(root: URL, transport: any PhoneProductTransport) {
    self.root = root
    self.transport = transport
    let idle = root.appendingPathComponent("unbound", isDirectory: true)
    outbox = PhoneOutbox(store: PhoneOutboxFileStore(directory: idle), gateway: transport)
    stops = PhoneStopFileStore(directory: idle)
  }

  /// Point later sends, lookups, and Stop at this connection. A different scope does not see the previous one.
  public func activate(_ scope: PhoneCacheScope) {
    guard let root, boundScope != scope.key else { return }
    boundScope = scope.key
    let directory = root.appendingPathComponent(scope.key, isDirectory: true)
    outbox = PhoneOutbox(store: PhoneOutboxFileStore(directory: directory), gateway: transport)
    stops = PhoneStopFileStore(directory: directory)
  }

  /// Keeps every owned conversation the product list names, including one with no title or preview.
  public static func visible(
    _ list: NessaConversationList, hiding deleted: Set<String>
  ) -> [NessaConversation] {
    list.conversations.filter { !deleted.contains($0.id) }
  }

  public func deliver(
    text: String, attachments: [DraftAttachment], conversationID: String,
    identity: MessageCommandIdentity
  ) async throws -> PhoneOutboxView {
    try requireBound()
    var images: [NessaImageAttachment] = []
    for attachment in attachments {
      images.append(try await transport.uploadPhoneImage(attachment, conversationID: conversationID))
    }
    let intent = try PhoneSendIntent(
      conversationID: conversationID, commandID: identity.requestID, turnID: identity.executionID,
      text: text, images: images)
    _ = try await outbox.hold(intent)
    return try await outbox.send(identity.requestID)
  }

  public func recover() async throws -> [PhoneOutboxView] {
    try requireBound()
    _ = try await recoverStops()
    return try await outbox.recover()
  }

  public func retry(_ commandID: String) async throws -> PhoneOutboxView {
    try requireBound()
    return try await outbox.retry(commandID)
  }

  public func list() async throws -> [PhoneOutboxView] {
    try requireBound()
    return try await outbox.list()
  }

  /// One Stop request id for this turn. A restart only looks it up. An explicit Stop sends
  /// again, with that same id, only when the lookup confirms the receipt is absent.
  public func stop(conversationID: String, executionID: String) async throws -> PhoneSendOutcome {
    try requireBound()
    var records = try await stops.load()
    if let existing = records.first(where: {
      $0.conversationID == conversationID && $0.executionID == executionID && $0.departed
    }) {
      let looked = try await recoverStop(existing, records: &records)
      guard looked == .unknown(.notAdmitted) else { return looked }
      var resent = existing
      resent.outcome = await finishStop(existing)
      replace(&records, resent)
      try await stops.save(records)
      return resent.outcome
    }
    let requestID = UUID().uuidString.lowercased()
    var record = PhoneStopRecord(
      conversationID: conversationID, requestID: requestID, executionID: executionID,
      departed: true, outcome: .unknown(.notAdmitted))
    records.append(record)
    try await stops.save(records)
    record.outcome = await finishStop(record)
    replace(&records, record)
    try await stops.save(records)
    return record.outcome
  }

  private func recoverStops() async throws -> [PhoneStopRecord] {
    var records = try await stops.load()
    for index in records.indices where records[index].departed && retryableStop(records[index]) {
      records[index].outcome = try await recoverStop(records[index], records: &records)
    }
    try await stops.save(records)
    return records
  }

  private func recoverStop(_ record: PhoneStopRecord, records: inout [PhoneStopRecord]) async throws
    -> PhoneSendOutcome
  {
    guard retryableStop(record) else { return record.outcome }
    let looked = await lookedUp(record)
    var updated = record
    updated.outcome = looked
    replace(&records, updated)
    try await stops.save(records)
    return updated.outcome
  }

  private func finishStop(_ record: PhoneStopRecord) async -> PhoneSendOutcome {
    let answer = await transport.phoneStop(
      conversationID: record.conversationID, requestID: record.requestID,
      executionID: record.executionID)
    if case .lost = answer { return await lookedUp(record) }
    if case .broken = answer { return await lookedUp(record) }
    return outcome(of: answer)
  }

  private func lookedUp(_ record: PhoneStopRecord) async -> PhoneSendOutcome {
    outcome(
      of: await transport.phoneLookupStop(
        conversationID: record.conversationID, requestID: record.requestID,
        executionID: record.executionID))
  }

  private func requireBound() throws {
    if root != nil, boundScope == nil { throw PhoneOutboxFailure.unavailable }
  }

  private func replace(_ records: inout [PhoneStopRecord], _ record: PhoneStopRecord) {
    if let index = records.firstIndex(where: { $0.requestID == record.requestID }) {
      records[index] = record
    }
  }
}

private func retryableStop(_ record: PhoneStopRecord) -> Bool {
  guard case .unknown(let cause) = record.outcome else { return false }
  return cause == .notAdmitted || cause == .lookupFailed
}

private func outcome(of answer: PhoneSendAnswer) -> PhoneSendOutcome {
  switch answer {
  case .receipt(.queued): .accepted
  case .receipt(.injected): .running
  case .receipt(.settled): .done
  case .refused("submission_unresolved"): .unknown(.unresolved)
  case .refused(let code): .failed(code)
  case .lost, .broken: .unknown(.lookupFailed)
  }
}

private func outcome(of answer: PhoneLookupAnswer) -> PhoneSendOutcome {
  switch answer {
  case .notFound: .unknown(.notAdmitted)
  case .lost, .broken: .unknown(.lookupFailed)
  case .conflict: .failed("submission_conflict")
  case .refused("submission_unresolved"): .unknown(.unresolved)
  case .refused(let code): .failed(code)
  case .found(let stage, let effect):
    switch stage {
    case "accepted": .accepted
    case "settled" where effect == "dispatched" || effect == "cancelled" || effect == "withdrawn":
      .done
    case "settled" where effect == "no_effect": .failed("revoked")
    case "attempted": .unknown(.attempted)
    default: .unknown(.lookupFailed)
    }
  }
}
