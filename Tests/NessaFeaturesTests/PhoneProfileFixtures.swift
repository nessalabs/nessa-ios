import Foundation

@testable import NessaFeatures

func profileIdentity(_ values: [String] = Array(repeating: "owner", count: 6))
  -> GatewaySessionSnapshot.Identity
{
  .init(
    gatewayID: values[0], principalID: values[1], organizationID: values[2],
    membershipID: values[3], credentialID: values[4], audienceID: values[5])
}
func exampleProfile(id: UUID = UUID(), phase: PhoneProfilePhase = .preparing) -> PhoneProfile {
  .init(
    id: id, phase: phase, productAddress: "ws://127.0.0.1:18743/session", instance: "phone",
    nativeAddress: "127.0.0.1:47650", identity: profileIdentity())
}
func exampleProfiles(_ profile: PhoneProfile = exampleProfile()) -> PhoneProfiles {
  .init(revision: UUID(), selected: profile.id, profiles: [profile])
}
func profileTestRoot() -> URL {
  FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    .resolvingSymlinksInPath()
}
func profileMetadataFile(_ root: URL) throws -> URL {
  try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
    .first(where: { $0.pathExtension == "json" })!
}

/// Faults use real atomic files and hold their actual lock; only the platform failure is substituted.
final class FaultingProfileFiles: PhoneProfileFileAccess, @unchecked Sendable {
  enum Mode {
    case beforeWrite, afterWrite, beforeSecondWrite, afterSecondWrite, failedReadback,
      differentReadback, heldWrite
  }
  let files: PrivatePhoneFiles
  let mode: Mode
  private let state = NSLock()
  private var written = false
  private var writes = 0
  let entered = DispatchSemaphore(value: 0)
  let release = DispatchSemaphore(value: 0)
  init(root: URL, mode: Mode) {
    files = PrivatePhoneFiles(root: root, maximumBytes: 1024 * 1024)
    self.mode = mode
  }
  func waitForEntry() async -> Bool {
    await withCheckedContinuation { continuation in
      DispatchQueue.global().async {
        continuation.resume(returning: self.entered.wait(timeout: .now() + 5) == .success)
      }
    }
  }
  func read(_ key: String) throws -> Data? {
    let after = state.withLock { written }
    if after && mode == .failedReadback { throw PrivatePhoneFileError.quota }
    return try files.read(key)
  }
  func write(_ data: Data, key: String) throws {
    let count = state.withLock {
      writes += 1
      return writes
    }
    if count == 1 && (mode == .beforeSecondWrite || mode == .afterSecondWrite) {
      try files.write(data, key: key)
      return
    }
    if mode == .heldWrite {
      entered.signal()
      release.wait()
      try files.write(data, key: key)
      return
    }
    if mode == .beforeWrite || mode == .beforeSecondWrite {
      throw PrivatePhoneFileError.unavailable
    }
    try files.write(mode == .differentReadback ? Data("different".utf8) : data, key: key)
    state.withLock { written = true }
    throw PrivatePhoneFileError.unavailable
  }
  func withLock<Value>(_ key: String, body: () throws -> Value) throws -> Value {
    try files.withLock(key, body: body)
  }
}

final class MemoryProfileKeychain: PhoneProfileKeychain, @unchecked Sendable {
  private let lock = NSLock()
  private var records: [String: Data]
  private var insertCount = 0
  let readFailure: PhoneProfileCredentialError?
  let competing: Data?
  init(
    records: [String: Data] = [:], readFailure: PhoneProfileCredentialError? = nil,
    competing: Data? = nil
  ) {
    self.records = records
    self.readFailure = readFailure
    self.competing = competing
  }
  var inserts: Int { lock.withLock { insertCount } }
  func read(reference: String) throws -> Data? {
    if let readFailure { throw readFailure }
    return lock.withLock { records[reference] }
  }
  func insert(_ data: Data, reference: String) throws {
    lock.withLock {
      insertCount += 1
      if records[reference] == nil { records[reference] = competing ?? data }
    }
  }
}
