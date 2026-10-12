import Darwin
import Foundation

/// Composition supplies an existing trusted sandbox root, not a saved container UUID.
public actor PhoneNativeLocations: PhoneNativeLocationPreparing {
  private let root: URL
  public init(root: URL) { self.root = root }
  public func prepare(_ profile: PhoneProfile) throws -> RetainedSessionLocation {
    let anchor = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
    guard anchor >= 0 else { throw PhoneProfileStoreError.storage(.unavailable) }
    var descriptors = [anchor]
    defer { for descriptor in descriptors.reversed() { close(descriptor) } }
    for component in profile.nativeDirectoryComponents {
      descriptors.append(try child(component, parent: descriptors.last!))
    }
    return RetainedSessionLocation(
      root: root.path, directory: profile.nativeDirectory, address: profile.nativeAddress)
  }
  /// Confines directory creation effects. The native opener still owns private-scope validation.
  private func child(_ name: String, parent: Int32) throws -> Int32 {
    guard mkdirat(parent, name, 0o700) == 0 || errno == EEXIST else {
      throw PhoneProfileStoreError.storage(.unavailable)
    }
    let descriptor = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
    guard descriptor >= 0 else { throw PhoneProfileStoreError.storage(.unavailable) }
    return descriptor
  }
}
