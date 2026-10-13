import CryptoKit
import Foundation

public enum PhoneDeletionStoreFailure: Error, Sendable {
  case changed, corrupt, capacity
  case write(PhoneProfilePublication, underlying: any Error, reconciliation: (any Error)?)
}
/// Durable pending deletion never substitutes absence or a local tombstone for a remote result.
public actor PhoneDeletionIntentStore: PhoneDeletionIntentStoring {
  private let files: any PrivatePhoneFileAccess
  public init(root: URL, maximumBytes: Int = 1024 * 1024) {
    files = PrivatePhoneFiles(root: root, maximumBytes: maximumBytes)
  }
  init(files: any PrivatePhoneFileAccess) { self.files = files }
  private func encode<Value: Encodable>(_ value: Value) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(value)
  }
  private struct DisplayRoute: Encodable {
    let selector: String
    let profileID: UUID?
  }
  private func routeKey(_ selector: String, profileID: UUID?) throws -> String {
    SHA256.hash(
      data: Data("phone-deletion-display:".utf8)
        + (try encode(DisplayRoute(selector: selector, profileID: profileID)))
    )
    .map { String(format: "%02x", $0) }.joined()
  }
  private func key(_ scope: PhoneDeletionScope) throws -> String {
    if let selector = scope.displaySelector {
      return try routeKey(selector, profileID: scope.profileID)
    }
    return SHA256.hash(data: Data("phone-deletion-intents:".utf8) + (try encode(scope)))
      .map { String(format: "%02x", $0) }.joined()
  }
  private func validate(_ records: [PhoneDeletionRecord], key expected: String) throws {
    guard records.count <= 64, Set(records.map { $0.intent.requestID }).count == records.count
    else { throw PhoneDeletionStoreFailure.capacity }
    for record in records {
      let intent = record.intent
      guard try key(intent.scope) == expected,
        record.acknowledgment == nil
          || record.acknowledgment?.requestId.utf8.elementsEqual(
            intent.requestID.uuidString.lowercased().utf8) == true
      else { throw PhoneDeletionStoreFailure.corrupt }
      try validateGatewayWire(
        encode(
          DeletionParams(
            conversationId: intent.conversationID,
            requestId: intent.requestID.uuidString.lowercased())), named: "ConversationDeleteParams"
      )
    }
  }
  private func read(key: String) throws -> [PhoneDeletionRecord] {
    guard let bytes = try files.read(key) else { return [] }
    let records = try JSONDecoder().decode([PhoneDeletionRecord].self, from: bytes)
    try validate(records, key: key)
    return records
  }
  public func load(scope: PhoneDeletionScope) throws -> [PhoneDeletionRecord] {
    try read(key: key(scope)).filter { $0.intent.scope == scope }
  }
  public func loadForDisplay(cache: PhoneCacheScope, profileID: UUID?) throws
    -> [PhoneDeletionRecord]
  {
    try read(key: routeKey(cache.key, profileID: profileID))
  }
  public func save(_ intent: PhoneDeletionIntent) throws {
    try update(intent.scope) { records in
      if let record = records.first(where: { $0.intent.requestID == intent.requestID }) {
        guard record.intent == intent else { throw PhoneDeletionStoreFailure.changed }
        return
      }
      records.append(.init(intent: intent))
    }
  }
  public func acknowledge(_ intent: PhoneDeletionIntent, value: PhoneDeletionAcknowledgment) throws
  {
    try update(intent.scope) { records in
      guard let index = records.firstIndex(where: { $0.intent == intent }),
        value.requestId.utf8.elementsEqual(intent.requestID.uuidString.lowercased().utf8),
        records[index].acknowledgment == nil || records[index].acknowledgment == value
      else { throw PhoneDeletionStoreFailure.changed }
      records[index] = .init(intent: intent, acknowledgment: value)
    }
  }
  private func update(
    _ scope: PhoneDeletionScope, change: (inout [PhoneDeletionRecord]) throws -> Void
  ) throws {
    let key = try key(scope)
    try files.withLock(key) {
      let prior = try files.read(key)
      var records = try read(key: key)
      try change(&records)
      try validate(records, key: key)
      let next = try encode(records)
      do { try publishPrivatePhoneRecord(next, prior: prior, key: key, files: files) } catch let
        failure as PrivatePhoneRecordWriteFailure
      {
        throw PhoneDeletionStoreFailure.write(
          failure.visibility, underlying: failure.underlying,
          reconciliation: failure.reconciliation)
      }
    }
  }
}
