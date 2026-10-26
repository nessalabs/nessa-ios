import Darwin
import Foundation

/// The linked desktop, kept as one private, atomically replaced file.
/// Removing it writes an empty record, so a half-removed desktop never reads
/// back as linked.
public actor LinkedDesktopFileStore: LinkedDesktopStoring {
  private struct Record: Codable { let desktop: LinkedDesktop? }
  /// The private-file key: SHA-256 of "linked-desktop", the 64 hex
  /// characters `PrivatePhoneFiles` requires of a key.
  private static let key = "dee4fb305789412a729af34141963fbec8b29e3c1b0b46feeda8899475519933"
  private let files: any PrivatePhoneFileAccess
  public init(root: URL) {
    files = PrivatePhoneFiles(
      root: root.appendingPathComponent("LinkedDesktop", isDirectory: true),
      maximumBytes: 64 * 1024)
  }
  init(files: any PrivatePhoneFileAccess) { self.files = files }
  public func load() throws -> LinkedDesktop? {
    try files.withLock(Self.key) {
      guard let data = try files.read(Self.key) else { return nil }
      return try JSONDecoder().decode(Record.self, from: data).desktop
    }
  }
  public func save(_ desktop: LinkedDesktop) throws {
    try files.withLock(Self.key) {
      try files.write(JSONEncoder().encode(Record(desktop: desktop)), key: Self.key)
    }
  }
  public func remove(_ id: UUID) throws {
    try files.withLock(Self.key) {
      guard let data = try files.read(Self.key),
        try JSONDecoder().decode(Record.self, from: data).desktop?.id == id
      else { return }
      try files.write(JSONEncoder().encode(Record(desktop: nil)), key: Self.key)
    }
  }
}

/// A linked desktop's native state, in its own directory under the trusted
/// root (`LinkedDesktops/<id>`), created owner-only without following links
/// as `PhoneNativeLocations` creates a profile's.
public actor LinkedDesktopLocations: LinkedDesktopLocating {
  private let root: URL
  public init(root: URL) { self.root = root }
  public func prepare(id: UUID, address: String) throws -> RetainedSessionLocation {
    try FileManager.default.createDirectory(
      at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let anchor = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
    guard anchor >= 0 else { throw DesktopLinkFailure.storage }
    var descriptors = [anchor]
    defer { for descriptor in descriptors.reversed() { close(descriptor) } }
    let components = LinkedDesktop.directoryComponents(for: id)
    for component in components {
      descriptors.append(try child(component, parent: descriptors.last!))
    }
    return RetainedSessionLocation(
      root: root.path, directory: components.joined(separator: "/"), address: address)
  }
  public func discard(id: UUID) {
    let directory = LinkedDesktop.directoryComponents(for: id).reduce(root) {
      $0.appendingPathComponent($1, isDirectory: true)
    }
    try? FileManager.default.removeItem(at: directory)
  }
  private func child(_ name: String, parent: Int32) throws -> Int32 {
    guard mkdirat(parent, name, 0o700) == 0 || errno == EEXIST else {
      throw DesktopLinkFailure.storage
    }
    let descriptor = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
    guard descriptor >= 0 else { throw DesktopLinkFailure.storage }
    return descriptor
  }
}
