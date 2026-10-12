import Foundation

/// Bounded, private derived display snapshots. Retained facts belong to the shared receiver.
public actor PhoneSnapshotStore: PhoneSnapshotStoring {
  private let files: PrivatePhoneFiles
  public init(root: URL? = nil, maximumBytes: Int = 16 * 1024 * 1024) {
    files = PrivatePhoneFiles(
      root: root
        ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Nessa/PhoneSnapshots", isDirectory: true),
      maximumBytes: maximumBytes)
  }
  public func load(_ scope: PhoneCacheScope) throws -> PhoneSnapshot? {
    do {
      guard let data = try files.read(scope.key) else { return nil }
      let snapshot = try JSONDecoder().decode(PhoneSnapshot.self, from: data)
      try snapshot.validate()
      return snapshot
    } catch PrivatePhoneFileError.quota { throw PhoneSnapshotError.quota } catch let error
      as PhoneSnapshotError
    { throw error } catch is DecodingError { throw PhoneSnapshotError.corrupt } catch {
      throw PhoneSnapshotError.unavailable
    }
  }
  public func save(_ snapshot: PhoneSnapshot, scope: PhoneCacheScope) throws {
    do {
      try snapshot.validate()
      var bounded = snapshot
      var data = try JSONEncoder().encode(bounded)
      while data.count > files.maximumBytes, !bounded.recentViews.isEmpty {
        bounded.views.removeValue(forKey: bounded.recentViews.removeFirst())
        data = try JSONEncoder().encode(bounded)
      }
      try files.write(data, key: scope.key)
    } catch PrivatePhoneFileError.quota { throw PhoneSnapshotError.quota } catch let error
      as PhoneSnapshotError
    { throw error } catch {
      throw PhoneSnapshotError.unavailable
    }
  }
}

public actor InMemoryPhoneSnapshotStore: PhoneSnapshotStoring {
  private var values: [String: PhoneSnapshot] = [:]
  public init() {}
  public func load(_ scope: PhoneCacheScope) -> PhoneSnapshot? { values[scope.key] }
  public func save(_ snapshot: PhoneSnapshot, scope: PhoneCacheScope) {
    values[scope.key] = snapshot
  }
}
public struct SystemRecoveryWait: RecoveryWaiting {
  public init() {}
  public func wait(for duration: Duration) async throws { try await Task.sleep(for: duration) }
}
