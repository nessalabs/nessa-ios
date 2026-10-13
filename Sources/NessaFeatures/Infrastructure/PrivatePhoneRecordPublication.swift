import Foundation

/// Readback describes visibility after a failed durable write, never successful durability.
struct PrivatePhoneRecordWriteFailure: Error {
  let visibility: PhoneProfilePublication
  let underlying: any Error
  let reconciliation: (any Error)?
}
func publishPrivatePhoneRecord(
  _ next: Data, prior: Data?, key: String, files: any PrivatePhoneFileAccess
) throws {
  do { try files.write(next, key: key) } catch {
    let failure = error
    let observed: Data?
    do { observed = try files.read(key) } catch {
      throw PrivatePhoneRecordWriteFailure(
        visibility: .uncertain, underlying: failure, reconciliation: error)
    }
    throw PrivatePhoneRecordWriteFailure(
      visibility: observed == next ? .published : (observed == prior ? .notPublished : .uncertain),
      underlying: failure, reconciliation: nil)
  }
}
