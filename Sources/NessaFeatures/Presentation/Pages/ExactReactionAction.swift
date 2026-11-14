/// A held message belongs to one delivery scope. A delayed tap on its palette may only
/// change the same scope's message, even when another profile uses the same chat and turn IDs.
enum ExactReactionAction {
  static func glyph(_ argument: String, scope: Int) -> String? {
    let prefix = "\(scope):"
    guard argument.hasPrefix(prefix) else { return nil }
    let value = String(argument.dropFirst(prefix.count))
    guard value.count == 1, value.unicodeScalars.contains(where: { $0.properties.isEmoji }) else { return nil }
    return value
  }
}
