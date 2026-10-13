import CryptoKit
import Foundation

/// Only derived-cache suppression. The caller holds the snapshot scope's lock.
enum SnapshotWithdrawalMarker {
  private struct Marker: Encodable {
    let schema = 1
    let scope: String
  }
  static func key(_ scope: PhoneCacheScope) -> String {
    SHA256.hash(data: Data(("phone-snapshot-withdrawal:" + scope.key).utf8))
      .map { String(format: "%02x", $0) }.joined()
  }
  private static func bytes(_ scope: PhoneCacheScope) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return try encoder.encode(Marker(scope: scope.key))
  }
  static func requireUnwithdrawn(_ scope: PhoneCacheScope, files: any PrivatePhoneFileAccess)
    throws
  {
    do {
      guard let stored = try files.read(key(scope)) else { return }
      guard stored == (try bytes(scope)) else {
        throw PhoneSnapshotError.withdrawal(.corrupt)
      }
      throw PhoneSnapshotError.withdrawn
    } catch let error as PhoneSnapshotError { throw error } catch {
      throw PhoneSnapshotError.withdrawal(failure(error))
    }
  }
  static func publish(_ scope: PhoneCacheScope, files: any PrivatePhoneFileAccess) throws {
    do {
      let key = key(scope)
      let expected = try bytes(scope)
      let prior = try files.read(key)
      guard prior == nil || prior == expected else {
        throw PhoneSnapshotWithdrawalError.marker(.corrupt)
      }
      // Always republish: visibility of a previous failed fsync is not durable completion.
      do { try files.write(expected, key: key) } catch {
        let primary = failure(error)
        let observed: Data?
        do { observed = try files.read(key) } catch {
          throw PhoneSnapshotWithdrawalError.write(
            .uncertain, primary, reconciliation: failure(error))
        }
        let publication: PhoneProfilePublication =
          observed == expected ? .published : (observed == prior ? .notPublished : .uncertain)
        throw PhoneSnapshotWithdrawalError.write(publication, primary, reconciliation: nil)
      }
    } catch let error as PhoneSnapshotWithdrawalError { throw error } catch {
      throw PhoneSnapshotWithdrawalError.marker(failure(error))
    }
  }
  static func failure(_ error: any Error) -> PhoneSnapshotMarkerFailure {
    if case PrivatePhoneFileError.quota = error { return .quota }
    return .unavailable
  }
}
