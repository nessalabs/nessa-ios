import CryptoKit
import Foundation

/// Identifies the exact permission and connection displayed before an asynchronous tap.
enum ExactPermissionAction {
  static func digest(_ review: NessaPermission) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    guard let data = try? encoder.encode(review) else { return "" }
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  static func stamp(_ review: NessaPermission, scope: Int, connection: Int) -> String {
    let digest = digest(review)
    return digest.isEmpty ? "" : "\(scope):\(connection):\(digest)"
  }

  static func option(_ id: String, stamp: String, review: NessaPermission,
    scope: Int, connection: Int) -> NessaPermission.Option?
  {
    guard !stamp.isEmpty, stamp == self.stamp(review, scope: scope, connection: connection) else { return nil }
    return review.options.first { $0.id == id }
  }
}
