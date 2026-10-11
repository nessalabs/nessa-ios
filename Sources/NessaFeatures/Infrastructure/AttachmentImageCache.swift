import CryptoKit
import Foundation

/// Device-local, bounded cache for uploads. Scope prevents images leaking between gateway identities.
actor AttachmentImageCache {
  private let directory: URL
  private let maximumBytes = 100 * 1024 * 1024
  init(scope: String) {
    let key = SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined()
    directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("Nessa/Images/" + key, isDirectory: true)
  }
  private func file(_ digest: String) -> URL? {
    let key = String(digest.dropFirst(7))
    guard digest.hasPrefix("sha256:"), key.count == 64,
      key.allSatisfy({ "0123456789abcdef".contains($0) })
    else { return nil }
    return directory.appendingPathComponent(key)
  }
  func read(_ digest: String) -> Data? {
    guard let url = file(digest), let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
      let size = values.fileSize, size > 0, size <= 5 * 1024 * 1024
    else { return nil }
    guard let data = try? Data(contentsOf: url) else { return nil }
    try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
    return data
  }
  func store(_ data: Data, digest: String) {
    guard let url = file(digest), data.count <= 5 * 1024 * 1024 else { return }
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try data.write(to: url, options: .atomic)
      let files = try FileManager.default.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])
      let entries = files.compactMap { url -> (URL, Int, Date)? in
        guard let v = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        else { return nil }
        return (url, v.fileSize ?? 0, v.contentModificationDate ?? .distantPast)
      }.sorted { $0.2 < $1.2 }
      var total = entries.reduce(0) { $0 + $1.1 }
      for entry in entries where total > maximumBytes {
        try FileManager.default.removeItem(at: entry.0)
        total -= entry.1
      }
    } catch { /* Cache failure must not prevent delivery. */  }
  }
}
