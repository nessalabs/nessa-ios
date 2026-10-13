import Foundation

/// Bounded, private derived display snapshots. Retained facts belong to the shared receiver.
public actor PhoneSnapshotStore: PhoneSnapshotStoring, PhoneSnapshotWithdrawing {
  private let files: any PrivatePhoneFileAccess
  private let maximumBytes: Int
  public init(root: URL? = nil, maximumBytes: Int = 16 * 1024 * 1024) {
    self.maximumBytes = maximumBytes
    files = PrivatePhoneFiles(
      root: root
        ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Nessa/PhoneSnapshots", isDirectory: true),
      maximumBytes: maximumBytes)
  }
  init(files: any PrivatePhoneFileAccess, maximumBytes: Int = 16 * 1024 * 1024) {
    precondition(maximumBytes > 0)
    self.files = files
    self.maximumBytes = maximumBytes
  }
  public func load(_ scope: PhoneCacheScope) throws -> PhoneSnapshot? {
    try transaction(scope) {
      try snapshotIO {
        guard let data = try files.read(scope.key) else { return nil }
        let snapshot = try JSONDecoder().decode(PhoneSnapshot.self, from: data)
        try snapshot.validate()
        return snapshot
      }
    }
  }
  public func save(_ snapshot: PhoneSnapshot, scope: PhoneCacheScope) throws {
    try transaction(scope) {
      try snapshotIO {
        try snapshot.validate()
        var bounded = snapshot
        var data = try JSONEncoder().encode(bounded)
        while data.count > maximumBytes, !bounded.recentViews.isEmpty {
          bounded.views.removeValue(forKey: bounded.recentViews.removeFirst())
          data = try JSONEncoder().encode(bounded)
        }
        guard data.count <= maximumBytes else { throw PhoneSnapshotError.quota }
        try files.write(data, key: scope.key)
      }
    }
  }
  public func withdraw(_ scope: PhoneCacheScope) throws {
    do {
      try files.withLock(scope.key) {
        try SnapshotWithdrawalMarker.publish(scope, files: files)
      }
    } catch let error as PhoneSnapshotWithdrawalError { throw error } catch {
      throw PhoneSnapshotWithdrawalError.marker(SnapshotWithdrawalMarker.failure(error))
    }
  }
  private func transaction<Value>(_ scope: PhoneCacheScope, body: () throws -> Value) throws
    -> Value
  {
    do {
      return try files.withLock(scope.key) {
        try SnapshotWithdrawalMarker.requireUnwithdrawn(scope, files: files)
        return try body()
      }
    } catch let error as PhoneSnapshotError { throw error } catch {
      throw PhoneSnapshotError.withdrawal(SnapshotWithdrawalMarker.failure(error))
    }
  }
  private func snapshotIO<Value>(_ body: () throws -> Value) throws -> Value {
    do {
      return try body()
    } catch PrivatePhoneFileError.quota { throw PhoneSnapshotError.quota } catch let error
      as PhoneSnapshotError
    { throw error } catch {
      if error is DecodingError { throw PhoneSnapshotError.corrupt }
      throw PhoneSnapshotError.unavailable
    }
  }
}

public actor InMemoryPhoneSnapshotStore: PhoneSnapshotStoring, PhoneSnapshotWithdrawing {
  private var values: [String: PhoneSnapshot] = [:]
  private var withdrawn: Set<String> = []
  public init() {}
  public func load(_ scope: PhoneCacheScope) throws -> PhoneSnapshot? {
    guard !withdrawn.contains(scope.key) else { throw PhoneSnapshotError.withdrawn }
    return values[scope.key]
  }
  public func save(_ snapshot: PhoneSnapshot, scope: PhoneCacheScope) throws {
    guard !withdrawn.contains(scope.key) else { throw PhoneSnapshotError.withdrawn }
    values[scope.key] = snapshot
  }
  public func withdraw(_ scope: PhoneCacheScope) { withdrawn.insert(scope.key) }
}
public struct SystemRecoveryWait: RecoveryWaiting {
  public init() {}
  public func wait(for duration: Duration) async throws { try await Task.sleep(for: duration) }
}
