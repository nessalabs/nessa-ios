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
  private let outbox: PhoneOutbox
  private let transport: any PhoneProductTransport
  private let stops: any PhoneStopStoring
  public init(
    outbox: PhoneOutbox, transport: any PhoneProductTransport, stops: any PhoneStopStoring
  ) {
    self.outbox = outbox
    self.transport = transport
    self.stops = stops
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
    _ = try await recoverStops()
    return try await outbox.recover()
  }

  public func retry(_ commandID: String) async throws -> PhoneOutboxView {
    try await outbox.retry(commandID)
  }

  public func list() async throws -> [PhoneOutboxView] {
    try await outbox.list()
  }

  /// One Stop for this turn. A later call looks the first one up and does not stop again.
  public func stop(conversationID: String, executionID: String) async throws -> PhoneSendOutcome {
    var records = try await stops.load()
    if let existing = records.first(where: {
      $0.conversationID == conversationID && $0.executionID == executionID && $0.departed
    }) {
      return try await recoverStop(existing, records: &records)
    }
    let requestID = UUID().uuidString.lowercased()
    var record = PhoneStopRecord(
      conversationID: conversationID, requestID: requestID, executionID: executionID,
      departed: true, outcome: .unknown(.notAdmitted))
    records.append(record)
    try await stops.save(records)
    let answer = await transport.phoneStop(
      conversationID: conversationID, requestID: requestID, executionID: executionID)
    if case .lost = answer {
      record.outcome = await lookedUp(record)
    } else if case .broken = answer {
      record.outcome = await lookedUp(record)
    } else {
      record.outcome = outcome(of: answer)
    }
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

  private func lookedUp(_ record: PhoneStopRecord) async -> PhoneSendOutcome {
    outcome(
      of: await transport.phoneLookupStop(
        conversationID: record.conversationID, requestID: record.requestID,
        executionID: record.executionID))
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
