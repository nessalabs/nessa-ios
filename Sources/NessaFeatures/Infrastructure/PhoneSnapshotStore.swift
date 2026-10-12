import Darwin
import Foundation

/// Bounded, private derived display snapshots. Retained facts belong to the shared receiver.
public actor PhoneSnapshotStore: PhoneSnapshotStoring {
  private let root: URL
  private let maximumBytes: Int
  public init(root: URL? = nil, maximumBytes: Int = 16 * 1024 * 1024) {
    self.root =
      root
      ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Nessa/PhoneSnapshots", isDirectory: true)
    self.maximumBytes = maximumBytes
  }
  public func load(_ scope: PhoneCacheScope) throws -> PhoneSnapshot? {
    let file = root.appendingPathComponent(scope.key + ".json")
    guard FileManager.default.fileExists(atPath: file.path) else { return nil }
    do {
      let rootProperties = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
      guard rootProperties.isDirectory == true, rootProperties.isSymbolicLink != true
      else { throw PhoneSnapshotError.unavailable }
      let descriptor = open(file.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
      guard descriptor >= 0 else { throw PhoneSnapshotError.unavailable }
      let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
      defer { try? handle.close() }
      var metadata = stat()
      guard fstat(descriptor, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG
      else { throw PhoneSnapshotError.unavailable }
      guard metadata.st_size >= 0, metadata.st_size <= maximumBytes
      else { throw PhoneSnapshotError.quota }
      let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
      guard data.count <= maximumBytes else { throw PhoneSnapshotError.quota }
      let snapshot = try JSONDecoder().decode(PhoneSnapshot.self, from: data)
      try snapshot.validate()
      return snapshot
    } catch let error as PhoneSnapshotError { throw error } catch {
      if error is DecodingError { throw PhoneSnapshotError.corrupt }
      throw PhoneSnapshotError.unavailable
    }
  }
  public func save(_ snapshot: PhoneSnapshot, scope: PhoneCacheScope) throws {
    do {
      try snapshot.validate()
      var bounded = snapshot
      var data = try JSONEncoder().encode(bounded)
      while data.count > maximumBytes, !bounded.recentViews.isEmpty {
        bounded.views.removeValue(forKey: bounded.recentViews.removeFirst())
        data = try JSONEncoder().encode(bounded)
      }
      guard data.count <= maximumBytes else { throw PhoneSnapshotError.quota }
      try FileManager.default.createDirectory(
        at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
      let properties = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
      guard properties.isDirectory == true, properties.isSymbolicLink != true
      else { throw PhoneSnapshotError.unavailable }
      var privateRoot = root
      var resource = URLResourceValues()
      resource.isExcludedFromBackup = true
      try privateRoot.setResourceValues(resource)
      let file = root.appendingPathComponent(scope.key + ".json")
      #if os(iOS)
        try data.write(
          to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
      #else
        try data.write(to: file, options: .atomic)
      #endif
      try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
      let handle = try FileHandle(forWritingTo: file)
      defer { try? handle.close() }
      try handle.synchronize()
      let directory = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
      guard directory >= 0 else { throw PhoneSnapshotError.unavailable }
      defer { close(directory) }
      guard fsync(directory) == 0 else { throw PhoneSnapshotError.unavailable }
    } catch let error as PhoneSnapshotError { throw error } catch {
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
