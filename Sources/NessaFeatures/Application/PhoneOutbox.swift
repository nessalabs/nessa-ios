import Foundation

/// Foreground `conversation.send` calls one live attempt may make, the first included.
/// A restart does not continue the count. It reads `conversation.receipt`.
public let phoneForegroundSends = 3

/// Why a saved phone send is still unknown. The effect may have happened.
public enum PhoneUnknownCause: String, Codable, Equatable, Sendable {
  case notAdmitted
  case lookupFailed
  case attempted
  case unresolved
}

/// The five rendered outcomes from the phone send contract, plus a draft that has not been sent.
public enum PhoneSendOutcome: Equatable, Sendable, Codable {
  case draft
  case accepted
  case running
  case done
  case failed(String)
  case unknown(PhoneUnknownCause)

  public var claimsSubmission: Bool {
    switch self {
    case .accepted, .running, .done: true
    case .draft, .failed, .unknown: false
    }
  }

  /// A person can ask again only when the effect may not have been admitted.
  public var admitsRetry: Bool {
    switch self {
    case .unknown(.notAdmitted), .unknown(.lookupFailed): true
    default: false
    }
  }
}

public enum PhoneDelivery: String, Equatable, Sendable {
  case queued, injected, settled
}

public enum PhoneSendAnswer: Equatable, Sendable {
  case receipt(PhoneDelivery)
  case refused(String)
  case lost
  case broken
}

public enum PhoneLookupAnswer: Equatable, Sendable {
  case found(stage: String, effect: String?)
  case notFound
  case refused(String)
  case conflict
  case lost
  case broken
}

public enum PhoneOutboxFailure: Error, Equatable, Sendable {
  case invalid
  case notHeld
  case conflict
  case unavailable
  case uncertain
  case unsaved
  case corrupt
}

enum PhoneOutboxStoreFailure: Error, Equatable {
  case unavailable, uncertain, corrupt, conflict
}

/// One typed send. Its canonical bytes are what a retry and a lookup repeat.
public struct PhoneSendIntent: Equatable, Sendable, Codable {
  public let conversationID: String
  public let commandID: String
  public let turnID: String
  public let text: String
  public let images: [NessaImageAttachment]
  public let canonical: Data

  public init(
    conversationID: String, commandID: String, turnID: String, text: String,
    images: [NessaImageAttachment]
  ) throws {
    guard Self.identifier(commandID), Self.identifier(turnID), Self.conversation(conversationID),
      text.utf8.count <= 8192,
      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty,
      images.count <= 8, images.reduce(0, { $0 + $1.size }) <= 10 * 1024 * 1024,
      images.allSatisfy(Self.image)
    else { throw PhoneOutboxFailure.invalid }
    self.conversationID = conversationID
    self.commandID = commandID
    self.turnID = turnID
    self.text = text
    self.images = images
    canonical = Self.bytes(
      conversationID: conversationID, commandID: commandID, turnID: turnID, text: text,
      images: images)
  }

  private enum CodingKeys: String, CodingKey {
    case conversationID, commandID, turnID, text, images, canonical
  }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      conversationID: try values.decode(String.self, forKey: .conversationID),
      commandID: try values.decode(String.self, forKey: .commandID),
      turnID: try values.decode(String.self, forKey: .turnID),
      text: try values.decode(String.self, forKey: .text),
      images: try values.decode([NessaImageAttachment].self, forKey: .images))
    let stored = try values.decode(Data.self, forKey: .canonical)
    guard canonical == stored else {
      throw DecodingError.dataCorruptedError(
        forKey: .canonical, in: values, debugDescription: "Canonical bytes do not match the send.")
    }
  }

  public func encode(to encoder: Encoder) throws {
    var values = encoder.container(keyedBy: CodingKeys.self)
    try values.encode(conversationID, forKey: .conversationID)
    try values.encode(commandID, forKey: .commandID)
    try values.encode(turnID, forKey: .turnID)
    try values.encode(text, forKey: .text)
    try values.encode(images, forKey: .images)
    try values.encode(canonical, forKey: .canonical)
  }

  func sameBytes(_ other: PhoneSendIntent) -> Bool { canonical == other.canonical }

  private static func identifier(_ value: String) -> Bool {
    !value.isEmpty && value.utf8.count <= 256
  }
  private static func conversation(_ value: String) -> Bool {
    UUID(uuidString: value)?.uuidString.lowercased() == value
  }
  private static func image(_ image: NessaImageAttachment) -> Bool {
    image.size > 0 && image.size <= 5 * 1024 * 1024
      && ["image/png", "image/jpeg", "image/gif", "image/webp"].contains(image.mimeType)
      && image.digest.hasPrefix("sha256:") && image.digest.count == 71
      && image.digest.dropFirst(7).utf8.allSatisfy {
        (48...57).contains($0) || (97...102).contains($0)
      }
  }
  private static func bytes(
    conversationID: String, commandID: String, turnID: String, text: String,
    images: [NessaImageAttachment]
  ) -> Data {
    let object: [String: Any] = [
      "commandId": commandID,
      "conversationId": conversationID,
      "images": images.map {
        ["digest": $0.digest, "mimeType": $0.mimeType, "size": $0.size] as [String: Any]
      },
      "text": text,
      "turnId": turnID,
      "v": 1,
    ]
    return (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
  }
}

public struct PhoneOutboxView: Equatable, Sendable, Identifiable {
  public var id: String { commandID }
  public let commandID: String
  public let turnID: String
  public let conversationID: String
  public let text: String
  public let images: [NessaImageAttachment]
  public let outcome: PhoneSendOutcome
  public let successor: String?
}

struct PhoneOutboxRecord: Equatable, Codable, Sendable {
  var intent: PhoneSendIntent
  var departed: Bool
  var outcome: PhoneSendOutcome
  var sends: Int
  var successor: String?

  static func held(_ intent: PhoneSendIntent) -> PhoneOutboxRecord {
    PhoneOutboxRecord(intent: intent, departed: false, outcome: .draft, sends: 0, successor: nil)
  }
  func depart() -> PhoneOutboxRecord? {
    guard !departed, outcome == .draft else { return nil }
    return PhoneOutboxRecord(
      intent: intent, departed: true, outcome: .unknown(.notAdmitted), sends: sends,
      successor: successor)
  }
  func with(outcome: PhoneSendOutcome) -> PhoneOutboxRecord {
    PhoneOutboxRecord(
      intent: intent, departed: departed, outcome: outcome, sends: sends, successor: successor)
  }
  func with(sends: Int) -> PhoneOutboxRecord {
    PhoneOutboxRecord(
      intent: intent, departed: departed, outcome: outcome, sends: sends, successor: successor)
  }
  func with(successor: String) -> PhoneOutboxRecord {
    PhoneOutboxRecord(
      intent: intent, departed: departed, outcome: outcome, sends: sends, successor: successor)
  }
  var view: PhoneOutboxView {
    PhoneOutboxView(
      commandID: intent.commandID, turnID: intent.turnID, conversationID: intent.conversationID,
      text: intent.text, images: intent.images, outcome: outcome, successor: successor)
  }
}

protocol PhoneOutboxStoring: Sendable {
  func load(_ id: String) async throws -> PhoneOutboxRecord?
  func insert(_ record: PhoneOutboxRecord) async throws
  func replace(_ previous: PhoneOutboxRecord, with next: PhoneOutboxRecord) async throws
  func replaceAndInsert(
    previous: PhoneOutboxRecord, next: PhoneOutboxRecord, draft: PhoneOutboxRecord
  ) async throws
  func list() async throws -> [PhoneOutboxRecord]
}

protocol PhoneOutboxAsking: Sendable {
  func send(_ intent: PhoneSendIntent) async -> PhoneSendAnswer
  func lookup(_ intent: PhoneSendIntent) async -> PhoneLookupAnswer
}

/// Saves a typed send before `conversation.send`, then renders the contract's outcome.
///
/// This is the phone's caller of `docs/design/phone-outbox.md`. The vendored Apple
/// package does not export `nessa-client-core`'s outbox. Ordering matches that
/// contract: a draft is not a submission, departure is durable before the gateway
/// is asked, and a restart reads `conversation.receipt` instead of sending again.
public actor PhoneOutbox {
  private let store: any PhoneOutboxStoring
  private let gateway: any PhoneOutboxAsking
  private let mint: @Sendable () -> (String, String)
  public init(
    store: any PhoneOutboxStoring, gateway: any PhoneOutboxAsking,
    mint: @escaping @Sendable () -> (String, String) = {
      (UUID().uuidString.lowercased(), UUID().uuidString.lowercased())
    }
  ) {
    self.store = store
    self.gateway = gateway
    self.mint = mint
  }

  public func hold(_ intent: PhoneSendIntent) async throws -> PhoneOutboxView {
    switch try await store.load(intent.commandID) {
    case nil:
      let record = PhoneOutboxRecord.held(intent)
      try await insert(record)
      return record.view
    case let existing? where existing.intent.sameBytes(intent):
      return existing.view
    case .some:
      throw PhoneOutboxFailure.conflict
    }
  }

  public func send(_ commandID: String) async throws -> PhoneOutboxView {
    guard let record = try await store.load(commandID) else { throw PhoneOutboxFailure.notHeld }
    if record.outcome != .draft { return try await reconcile(record, allowSend: false) }
    guard let departed = record.depart() else { throw PhoneOutboxFailure.conflict }
    try await persistBeforeSend(previous: record, next: departed)
    return try await foreground(departed, cause: .sendAnswered)
  }

  /// Looks up commands that may have left. Does not send.
  public func recover() async throws -> [PhoneOutboxView] {
    let pending = try await store.list().filter { $0.departed && retryable($0) }
    var views: [PhoneOutboxView] = []
    for record in pending {
      views.append(try await reconcile(record, allowSend: false))
    }
    return views
  }

  public func retry(_ commandID: String) async throws -> PhoneOutboxView {
    guard let record = try await store.load(commandID) else { throw PhoneOutboxFailure.notHeld }
    if record.outcome == .draft { return try await send(commandID) }
    guard retryable(record) else { return record.view }
    let answer = await gateway.lookup(record.intent)
    if case .notFound = answer {
      return try await sendAfterNotFound(original: record)
    }
    return try await applyLookup(record, answer: answer, allowSend: false)
  }

  public func list() async throws -> [PhoneOutboxView] {
    try await store.list().map(\.view)
  }

  private func sendAfterNotFound(original: PhoneOutboxRecord) async throws -> PhoneOutboxView {
    guard let record = try await store.load(original.intent.commandID) else {
      throw PhoneOutboxFailure.notHeld
    }
    guard record == original else { return record.view }
    let looked = record.with(outcome: .unknown(.notAdmitted))
    if let kept = try await askedOrKept(previous: record, next: looked) {
      return kept
    }
    let reset = looked.with(sends: 0)
    if let kept = try await askedOrKept(previous: looked, next: reset) {
      return kept
    }
    return try await foreground(reset, cause: .explicitRetry)
  }

  private func reconcile(_ record: PhoneOutboxRecord, allowSend: Bool) async throws
    -> PhoneOutboxView
  {
    guard retryable(record) else { return record.view }
    let answer = await gateway.lookup(record.intent)
    return try await applyLookup(record, answer: answer, allowSend: allowSend)
  }

  private func foreground(_ start: PhoneOutboxRecord, cause initial: Cause) async throws
    -> PhoneOutboxView
  {
    var record = start
    var cause = initial
    while true {
      if record.sends >= phoneForegroundSends {
        let next = record.with(outcome: .unknown(.notAdmitted))
        if let kept = try await askedOrKept(previous: record, next: next) {
          return kept
        }
        return next.view
      }
      let answer = await gateway.send(record.intent)
      switch afterSend(record, answer) {
      case .done(let next):
        return try await askedView(previous: record, next: next, cause: cause)
      case .returnToDraft(let next):
        return try await returnToDraft(previous: record, failed: next)
      case .lookup(let bumped, let resend):
        if let kept = try await askedOrKept(previous: record, next: bumped) {
          return kept
        }
        let looked = await gateway.lookup(bumped.intent)
        switch afterLookup(bumped, looked, allowSend: resend) {
        case .done(let next):
          return try await askedView(previous: bumped, next: next, cause: .lookup)
        case .returnToDraft(let next):
          return try await returnToDraft(previous: bumped, failed: next)
        case .send(let next):
          if let kept = try await askedOrKept(previous: bumped, next: next) {
            return kept
          }
          record = next
          cause = .foregroundSend
        case .lookup:
          throw PhoneOutboxFailure.unsaved
        }
      case .send:
        throw PhoneOutboxFailure.unsaved
      }
    }
  }

  private func applyLookup(
    _ record: PhoneOutboxRecord, answer: PhoneLookupAnswer, allowSend: Bool
  ) async throws -> PhoneOutboxView {
    switch afterLookup(record, answer, allowSend: allowSend) {
    case .done(let next):
      return try await askedView(previous: record, next: next, cause: .lookup)
    case .returnToDraft(let next):
      return try await returnToDraft(previous: record, failed: next)
    case .send(let next):
      if let kept = try await askedOrKept(previous: record, next: next) {
        return kept
      }
      return try await foreground(next, cause: .foregroundSend)
    case .lookup:
      throw PhoneOutboxFailure.unsaved
    }
  }

  private func returnToDraft(previous: PhoneOutboxRecord, failed: PhoneOutboxRecord) async throws
    -> PhoneOutboxView
  {
    if failed.successor != nil {
      return try await askedView(previous: previous, next: failed, cause: .returnedToDraft)
    }
    let (command, turn) = mint()
    let draftIntent = try PhoneSendIntent(
      conversationID: failed.intent.conversationID, commandID: command, turnID: turn,
      text: failed.intent.text, images: failed.intent.images)
    let draft = PhoneOutboxRecord.held(draftIntent)
    let failed = failed.with(successor: command)
    do {
      try await store.replaceAndInsert(previous: previous, next: failed, draft: draft)
      return failed.view
    } catch PhoneOutboxStoreFailure.conflict {
      return try await committed(previous)
    } catch {
      throw asked(error)
    }
  }

  private func persistBeforeSend(previous: PhoneOutboxRecord, next: PhoneOutboxRecord) async throws
  {
    do { try await store.replace(previous, with: next) } catch {
      throw map(error, askedGateway: false)
    }
  }

  private func insert(_ record: PhoneOutboxRecord) async throws {
    do { try await store.insert(record) } catch { throw map(error, askedGateway: false) }
  }

  private func askedOrKept(
    previous: PhoneOutboxRecord, next: PhoneOutboxRecord
  ) async throws -> PhoneOutboxView? {
    do {
      try await store.replace(previous, with: next)
      return nil
    } catch PhoneOutboxStoreFailure.conflict {
      return try await committed(previous)
    } catch {
      throw asked(error)
    }
  }

  private func askedView(
    previous: PhoneOutboxRecord, next: PhoneOutboxRecord, cause: Cause
  ) async throws -> PhoneOutboxView {
    _ = cause
    if let kept = try await askedOrKept(previous: previous, next: next) {
      return kept
    }
    return next.view
  }

  private func committed(_ previous: PhoneOutboxRecord) async throws -> PhoneOutboxView {
    switch try? await store.load(previous.intent.commandID) {
    case let saved?:
      return saved.view
    default:
      throw PhoneOutboxFailure.unsaved
    }
  }
}

private enum Cause {
  case sendAnswered, sendLost, unreadable, lookup, foregroundSend, explicitRetry, bound,
    returnedToDraft
}

private enum Step {
  case done(PhoneOutboxRecord)
  case lookup(PhoneOutboxRecord, resend: Bool)
  case send(PhoneOutboxRecord)
  case returnToDraft(PhoneOutboxRecord)
}

private func retryable(_ record: PhoneOutboxRecord) -> Bool {
  guard case .unknown(let cause) = record.outcome else { return false }
  return cause == .notAdmitted || cause == .lookupFailed
}

private func afterSend(_ record: PhoneOutboxRecord, _ answer: PhoneSendAnswer) -> Step {
  let record = record.with(sends: record.sends + 1)
  switch answer {
  case .receipt(.queued): return .done(record.with(outcome: .accepted))
  case .receipt(.injected): return .done(record.with(outcome: .running))
  case .receipt(.settled): return .done(record.with(outcome: .done))
  case .refused("submission_unresolved"):
    return .done(record.with(outcome: .unknown(.unresolved)))
  case .refused("turn_running"):
    return .returnToDraft(record.with(outcome: .failed("turn_running")))
  case .refused(let code):
    return .done(record.with(outcome: .failed(code)))
  case .lost:
    return .lookup(record, resend: true)
  case .broken:
    return .lookup(record, resend: false)
  }
}

private func afterLookup(
  _ record: PhoneOutboxRecord, _ answer: PhoneLookupAnswer, allowSend: Bool
) -> Step {
  switch answer {
  case .lost, .broken:
    return .done(record.with(outcome: .unknown(.lookupFailed)))
  case .notFound:
    let record = record.with(outcome: .unknown(.notAdmitted))
    if allowSend && record.sends < phoneForegroundSends { return .send(record) }
    return .done(record)
  case .conflict:
    return .done(record.with(outcome: .failed("submission_conflict")))
  case .refused("submission_unresolved"):
    return .done(record.with(outcome: .unknown(.unresolved)))
  case .refused("turn_running"):
    return .returnToDraft(record.with(outcome: .failed("turn_running")))
  case .refused(let code):
    return .done(record.with(outcome: .failed(code)))
  case .found(let stage, let effect):
    return .done(record.with(outcome: outcome(stage: stage, effect: effect)))
  }
}

private func outcome(stage: String, effect: String?) -> PhoneSendOutcome {
  switch stage {
  case "accepted": return .accepted
  case "attempted", "ready": return .unknown(.attempted)
  case "settled":
    switch effect {
    case "dispatched": return .done
    case "no_effect": return .failed("revoked")
    case "refused_after_save": return .failed("revoked_after_save")
    case "unavailable_after_save": return .failed("unavailable_after_save")
    default: return .unknown(.attempted)
    }
  default:
    return .unknown(.attempted)
  }
}

private func asked(_ error: any Error) -> PhoneOutboxFailure {
  switch map(error, askedGateway: true) {
  case .unavailable, .uncertain: return .unsaved
  case let failure: return failure
  }
}

private func map(_ error: any Error, askedGateway: Bool) -> PhoneOutboxFailure {
  guard let error = error as? PhoneOutboxStoreFailure else {
    return askedGateway ? .unsaved : .unavailable
  }
  switch error {
  case .unavailable: return .unavailable
  case .uncertain: return .uncertain
  case .corrupt: return .corrupt
  case .conflict: return .conflict
  }
}
