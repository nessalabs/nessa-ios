import CryptoKit
import Foundation

public actor PhoneProfileStore: PhoneProfileStoring {
  private let files: any PrivatePhoneFileAccess
  private let key = SHA256.hash(data: Data("phone-profile-registry".utf8))
    .map { String(format: "%02x", $0) }.joined()
  public init(root: URL, maximumBytes: Int = 1024 * 1024) {
    files = PrivatePhoneFiles(root: root, maximumBytes: maximumBytes)
  }
  init(files: any PrivatePhoneFileAccess) { self.files = files }
  private func encode(_ value: PhoneProfiles) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(value)
  }
  public func load() throws -> PhoneProfiles? {
    do {
      guard let bytes = try files.read(key) else { return nil }
      let value = try JSONDecoder().decode(PhoneProfiles.self, from: bytes)
      do { try value.validate() } catch { throw PhoneProfileStoreError.corrupt }
      return value
    } catch let error as PhoneProfileStoreError { throw error } catch is DecodingError {
      throw PhoneProfileStoreError.corrupt
    } catch { throw PhoneProfileStoreError.storage(Self.failure(error)) }
  }
  public func save(_ next: PhoneProfiles, replacing expected: PhoneProfiles?) throws {
    try next.validate(replacing: expected)
    do {
      let prior = try expected.map { try encode($0) }
      let bytes = try encode(next)
      try files.withLock(key) {
        guard try files.read(key) == prior else { throw PhoneProfileStoreError.changed }
        do { try files.write(bytes, key: key) } catch {
          let writeFailure = Self.failure(error)
          let observed: Data?
          do { observed = try files.read(key) } catch {
            throw PhoneProfileStoreError.write(
              .uncertain, writeFailure, reconciliation: Self.failure(error))
          }
          let publication: PhoneProfilePublication =
            observed == bytes
            ? .published
            : (observed == prior ? .notPublished : .uncertain)
          throw PhoneProfileStoreError.write(publication, writeFailure, reconciliation: nil)
        }
      }
    } catch let error as PhoneProfileStoreError { throw error } catch {
      throw PhoneProfileStoreError.storage(Self.failure(error))
    }
  }
  private static func failure(_ error: any Error) -> PhoneProfileStorageFailure {
    if case PrivatePhoneFileError.quota = error { return .quota }
    return .unavailable
  }
}
