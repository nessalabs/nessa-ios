import Foundation

struct FileTextPreview: Sendable {
  static let maximumBytes = 16 * 1024
  let text: String
  let truncated: Bool

  static func prepare(_ data: Data) -> FileTextPreview? {
    let truncated = data.count > maximumBytes
    var prefix = Data(data.prefix(maximumBytes))
    // A bounded UTF-8 prefix can end partway through a character.
    for attempt in 0...(truncated ? 3 : 0) {
      if let text = String(data: prefix, encoding: .utf8) {
        return FileTextPreview(text: text, truncated: truncated)
      }
      if attempt < 3, !prefix.isEmpty { prefix.removeLast() }
    }
    return nil
  }
}
