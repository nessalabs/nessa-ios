import CryptoKit
import Foundation

/// Visibility after a failed write does not establish successful durability.
public struct PhoneOwnerApprovalWriteFailure: Error, Sendable {
  public let visibility: PhoneProfilePublication
  public let underlying: any Error
  public let reconciliation: (any Error)?
}

/// Private storage for original nonselected setup facts; it does not authorize a device.
public actor PhoneOwnerApprovalStore: PhoneOwnerApprovalStoring {
  private let files: any PrivatePhoneFileAccess
  private let key = SHA256.hash(data: Data("phone-owner-approval-journal".utf8))
    .map { String(format: "%02x", $0) }.joined()

  public init(root: URL, maximumBytes: Int = 1024 * 1024) {
    files = PrivatePhoneFiles(root: root, maximumBytes: maximumBytes)
  }
  init(files: any PrivatePhoneFileAccess) { self.files = files }

  public func load() throws -> [PhoneOwnerApprovalRecord] {
    guard let bytes = try files.read(key) else { return [] }
    return try JSONDecoder().decode([PhoneOwnerApprovalRecord].self, from: bytes)
  }

  public func publish(
    _ records: [PhoneOwnerApprovalRecord], replacing expected: [PhoneOwnerApprovalRecord]
  ) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let previous = try encoder.encode(expected)
    let next = try encoder.encode(records)
    try files.withLock(key) {
      let prior = try files.read(key)
      guard prior == previous || (prior == nil && expected.isEmpty) else {
        throw PhoneOwnerApprovalRefusal.changed
      }
      // Equal visible records still require this physical publication to succeed.
      do { try publishPrivatePhoneRecord(next, prior: prior, key: key, files: files) } catch let
        failure as PrivatePhoneRecordWriteFailure
      {
        throw PhoneOwnerApprovalWriteFailure(
          visibility: failure.visibility, underlying: failure.underlying,
          reconciliation: failure.reconciliation)
      }
    }
  }
}
