import CryptoKit
import Foundation

public enum PhoneConversationShareStoreFailure: Error, Sendable {
  case changed, corrupt, capacity
  case write(PhoneProfilePublication, underlying: any Error, reconciliation: (any Error)?)
}
/// Protected non-secret intents and historical acknowledgments; current grants stay remote-owned.
public actor PhoneConversationShareIntentStore: PhoneConversationShareIntentStoring {
  private let files: any PrivatePhoneFileAccess
  public init(root: URL, maximumBytes: Int = 1024 * 1024) {
    files = PrivatePhoneFiles(root: root, maximumBytes: maximumBytes)
  }
  init(files: any PrivatePhoneFileAccess) { self.files = files }
  private func key(_ id: UUID) -> String {
    SHA256.hash(data: Data(("phone-conversation-share-intents:" + id.uuidString.lowercased()).utf8))
      .map { String(format: "%02x", $0) }.joined()
  }
  private func validate(_ records: [PhoneConversationShareRecord], profileID: UUID) throws {
    guard records.count <= 64, Set(records.map { $0.intent.requestID }).count == records.count
    else { throw PhoneConversationShareStoreFailure.capacity }
    for record in records {
      let i = record.intent
      guard i.profileID == profileID, let credential = i.device.credentialID,
        i.device.phase == .active, i.device.receiver != nil,
        record.acknowledgment == nil
          || record.acknowledgment?.requestId == i.requestID.uuidString.lowercased()
      else { throw PhoneConversationShareStoreFailure.corrupt }
      try validateGatewayWire(
        JSONEncoder().encode(
          SharingRead(
            conversationId: i.conversationID,
            requestId: i.requestID.uuidString.lowercased(), credentialId: credential, role: "read")),
        named: "ConversationShareParams")
    }
  }
  private func read(_ id: UUID) throws -> [PhoneConversationShareRecord] {
    guard let bytes = try files.read(key(id)) else { return [] }
    let records = try JSONDecoder().decode([PhoneConversationShareRecord].self, from: bytes)
    try validate(records, profileID: id)
    return records
  }
  public func load(profileID: UUID) throws -> [PhoneConversationShareRecord] { try read(profileID) }
  public func save(_ intent: PhoneConversationShareIntent) throws {
    try update(intent.profileID) { records in
      if let saved = records.first(where: { $0.intent.requestID == intent.requestID }) {
        guard saved.intent == intent else { throw PhoneConversationShareStoreFailure.changed }
        return
      }
      records.append(.init(intent: intent))
    }
  }
  public func acknowledge(
    _ intent: PhoneConversationShareIntent, value: PhoneConversationShareAcknowledgment
  ) throws {
    try update(intent.profileID) { records in
      guard let index = records.firstIndex(where: { $0.intent == intent }),
        value.requestId.utf8.elementsEqual(intent.requestID.uuidString.lowercased().utf8),
        records[index].acknowledgment == nil || records[index].acknowledgment == value
      else { throw PhoneConversationShareStoreFailure.changed }
      records[index] = .init(intent: intent, acknowledgment: value)
    }
  }
  private func update(_ id: UUID, change: (inout [PhoneConversationShareRecord]) throws -> Void)
    throws
  {
    let key = key(id)
    try files.withLock(key) {
      let prior = try files.read(key)
      var records = try read(id)
      try change(&records)
      try validate(records, profileID: id)
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      let next = try encoder.encode(records)
      do { try publishPrivatePhoneRecord(next, prior: prior, key: key, files: files) } catch let
        failure as PrivatePhoneRecordWriteFailure
      {
        throw PhoneConversationShareStoreFailure.write(
          failure.visibility, underlying: failure.underlying, reconciliation: failure.reconciliation
        )
      }
    }
  }
}
