import Darwin
import Foundation

enum PrivatePhoneFileError: Error { case quota, unavailable }

/// Synchronous transactions hold one private-file lock through write reconciliation.
protocol PrivatePhoneFileAccess: Sendable {
  func read(_ key: String) throws -> Data?
  func write(_ data: Data, key: String) throws
  func withLock<Value>(_ key: String, body: () throws -> Value) throws -> Value
}

/// Reusable bounded, atomic private-file I/O. Call on an infrastructure actor.
struct PrivatePhoneFiles: PrivatePhoneFileAccess {
  let root: URL
  let maximumBytes: Int
  init(root: URL, maximumBytes: Int) {
    precondition(maximumBytes > 0)
    self.root = root
    self.maximumBytes = maximumBytes
  }
  private func file(_ key: String) throws -> URL {
    guard key.utf8.count == 64,
      key.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
    else { throw PrivatePhoneFileError.unavailable }
    return root.appendingPathComponent(key + ".json")
  }
  private func validateRoot() throws {
    let properties = try root.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
    guard properties.isDirectory == true, properties.isSymbolicLink != true
    else { throw PrivatePhoneFileError.unavailable }
  }
  func read(_ key: String) throws -> Data? {
    let file = try file(key)
    var metadata = stat()
    if lstat(file.path, &metadata) != 0 {
      if errno == ENOENT { return nil }
      throw PrivatePhoneFileError.unavailable
    }
    try validateRoot()
    let descriptor = open(file.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
    guard descriptor >= 0 else { throw PrivatePhoneFileError.unavailable }
    let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    defer { try? handle.close() }
    guard fstat(descriptor, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG
    else { throw PrivatePhoneFileError.unavailable }
    guard metadata.st_size >= 0, metadata.st_size <= maximumBytes
    else { throw PrivatePhoneFileError.quota }
    let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
    guard data.count <= maximumBytes else { throw PrivatePhoneFileError.quota }
    return data
  }
  func write(_ data: Data, key: String) throws {
    guard data.count <= maximumBytes else { throw PrivatePhoneFileError.quota }
    let file = try file(key)
    try FileManager.default.createDirectory(
      at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    try validateRoot()
    var metadata = stat()
    if lstat(file.path, &metadata) == 0 {
      guard metadata.st_mode & S_IFMT == S_IFREG else { throw PrivatePhoneFileError.unavailable }
    } else if errno != ENOENT {
      throw PrivatePhoneFileError.unavailable
    }
    var privateRoot = root
    var resource = URLResourceValues()
    resource.isExcludedFromBackup = true
    try privateRoot.setResourceValues(resource)
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
    guard directory >= 0 else { throw PrivatePhoneFileError.unavailable }
    defer { close(directory) }
    guard fsync(directory) == 0 else { throw PrivatePhoneFileError.unavailable }
  }
  /// Stable lock inode. It is never unlinked during normal journal operation.
  func withLock<T>(_ key: String, body: () throws -> T) throws -> T {
    let file = try file(key).deletingPathExtension().appendingPathExtension("lock")
    try FileManager.default.createDirectory(
      at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    try validateRoot()
    let descriptor = open(file.path, O_RDWR | O_CREAT | O_NOFOLLOW | O_NONBLOCK, 0o600)
    guard descriptor >= 0 else { throw PrivatePhoneFileError.unavailable }
    defer { close(descriptor) }
    var metadata = stat()
    guard fstat(descriptor, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG,
      flock(descriptor, LOCK_EX | LOCK_NB) == 0
    else { throw PrivatePhoneFileError.unavailable }
    defer { _ = flock(descriptor, LOCK_UN) }
    return try body()
  }
}
