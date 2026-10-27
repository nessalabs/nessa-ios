import Foundation

/// One scope's product operations; the factory binds every effect and lookup.
protocol PhoneProductTransport: PhoneOutboxAsking {
  func uploadPhoneAttachment(_ attachment: DraftAttachment, conversationID: String) async throws
    -> NessaStoredAttachment
  func phoneStop(conversationID: String, requestID: String, executionID: String) async
    -> PhoneSendAnswer
  func phoneLookupStop(conversationID: String, requestID: String, executionID: String) async
    -> PhoneLookupAnswer
}

protocol PhoneProductTransportFactory: Sendable {
  nonisolated func transport(for scope: PhoneCacheScope) -> any PhoneProductTransport
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
/// and send text, images or files through the outbox.
public actor PhoneProductChat {
  private struct Scope: Sendable {
    let key: String?
    let transport: any PhoneProductTransport
    let outbox: PhoneOutbox
    let stops: any PhoneStopStoring
  }
  private var current: Scope?
  private let root: URL?
  private let factory: (any PhoneProductTransportFactory)?
  /// Explicit single-scope application fixture; live wiring always uses the factory.
  init(outbox: PhoneOutbox, transport: any PhoneProductTransport, stops: any PhoneStopStoring) {
    current = Scope(key: nil, transport: transport, outbox: outbox, stops: stops)
    root = nil
    factory = nil
  }
  init(root: URL, transport: any PhoneProductTransportFactory) {
    self.root = root
    self.factory = transport
    current = nil
  }
  public func activate(_ scope: PhoneCacheScope) {
    guard current?.key != scope.key else { return }
    guard let root, let factory else {
      if let current {
        self.current = Scope(
          key: scope.key, transport: current.transport, outbox: current.outbox, stops: current.stops
        )
      }
      return
    }
    let directory = root.appendingPathComponent(scope.key, isDirectory: true)
    let transport = factory.transport(for: scope)
    current = Scope(
      key: scope.key, transport: transport,
      outbox: PhoneOutbox(store: PhoneOutboxFileStore(directory: directory), gateway: transport),
      stops: PhoneStopFileStore(directory: directory))
  }

  /// Keeps every owned conversation the product list names, including one with no title or preview.
  public static func visible(
    _ list: NessaConversationList, hiding deleted: Set<String>
  ) -> [NessaConversation] {
    list.conversations.filter { !deleted.contains($0.id) }
  }

  public func deliver(
    text: String, attachments: [DraftAttachment], conversationID: String,
    identity: MessageCommandIdentity, scope expected: PhoneCacheScope?
  ) async throws -> PhoneOutboxView {
    let scope = try requireBound(expected)
    try AttachmentPolicy.nessa.validate(attachments)
    var images: [NessaStoredAttachment] = []
    var uploads: [NessaUploadedFile] = []
    for attachment in attachments {
      let stored = try await scope.transport.uploadPhoneAttachment(
        attachment, conversationID: conversationID)
      guard scope.key == current?.key else { throw NessaGatewayError.disconnected }
      if attachment.isImage {
        images.append(stored)
      } else {
        uploads.append(NessaUploadedFile(stored, name: attachment.name))
      }
    }
    let intent = try PhoneSendIntent(
      conversationID: conversationID, commandID: identity.requestID, turnID: identity.executionID,
      text: text, images: images, uploads: uploads)
    guard scope.key == current?.key else { throw NessaGatewayError.disconnected }
    _ = try await scope.outbox.hold(intent)
    return try await scope.outbox.send(identity.requestID)
  }

  public func recover(scope expected: PhoneCacheScope?) async throws -> [PhoneOutboxView] {
    let scope = try requireBound(expected)
    _ = try await recoverStops(scope)
    return try await scope.outbox.recover()
  }

  public func retry(_ commandID: String, scope expected: PhoneCacheScope?) async throws
    -> PhoneOutboxView
  {
    let scope = try requireBound(expected)
    return try await scope.outbox.retry(commandID)
  }

  public func list(scope expected: PhoneCacheScope?) async throws -> [PhoneOutboxView] {
    let scope = try requireBound(expected)
    return try await scope.outbox.list()
  }

  /// One Stop request id for this turn. A restart only looks it up. An explicit Stop sends
  /// again, with that same id, only when the lookup confirms the receipt is absent.
  public func stop(conversationID: String, executionID: String, scope expected: PhoneCacheScope?)
    async throws -> PhoneSendOutcome
  {
    let scope = try requireBound(expected)
    var records = try await scope.stops.load()
    if let existing = records.first(where: {
      $0.conversationID == conversationID && $0.executionID == executionID && $0.departed
    }) {
      let looked = try await recoverStop(existing, records: &records, scope: scope)
      guard looked == .unknown(.notAdmitted) else { return looked }
      var resent = existing
      resent.outcome = await finishStop(existing, scope: scope)
      replace(&records, resent)
      try await scope.stops.save(records)
      return resent.outcome
    }
    let requestID = UUID().uuidString.lowercased()
    var record = PhoneStopRecord(
      conversationID: conversationID, requestID: requestID, executionID: executionID,
      departed: true, outcome: .unknown(.notAdmitted))
    records.append(record)
    try await scope.stops.save(records)
    record.outcome = await finishStop(record, scope: scope)
    replace(&records, record)
    try await scope.stops.save(records)
    return record.outcome
  }

  private func recoverStops(_ scope: Scope) async throws -> [PhoneStopRecord] {
    var records = try await scope.stops.load()
    for index in records.indices where records[index].departed && retryableStop(records[index]) {
      records[index].outcome = try await recoverStop(
        records[index], records: &records, scope: scope)
    }
    try await scope.stops.save(records)
    return records
  }

  private func recoverStop(
    _ record: PhoneStopRecord, records: inout [PhoneStopRecord], scope: Scope
  ) async throws
    -> PhoneSendOutcome
  {
    guard retryableStop(record) else { return record.outcome }
    let looked = await lookedUp(record, scope: scope)
    var updated = record
    updated.outcome = looked
    replace(&records, updated)
    try await scope.stops.save(records)
    return updated.outcome
  }

  private func finishStop(_ record: PhoneStopRecord, scope: Scope) async -> PhoneSendOutcome {
    let answer = await scope.transport.phoneStop(
      conversationID: record.conversationID, requestID: record.requestID,
      executionID: record.executionID)
    if case .lost = answer { return await lookedUp(record, scope: scope) }
    if case .broken = answer { return await lookedUp(record, scope: scope) }
    return outcome(of: answer)
  }

  private func lookedUp(_ record: PhoneStopRecord, scope: Scope) async -> PhoneSendOutcome {
    outcome(
      of: await scope.transport.phoneLookupStop(
        conversationID: record.conversationID, requestID: record.requestID,
        executionID: record.executionID))
  }

  private func requireBound(_ expected: PhoneCacheScope?) throws -> Scope {
    guard let current, current.key == expected?.key else { throw PhoneOutboxFailure.unavailable }
    return current
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
