import Foundation

public struct MessageReply: Equatable, Sendable {
  public let id: String
  public let author: String
  public let text: String

  public var context: String {
    "> " + String(text.prefix(500)).replacingOccurrences(of: "\n", with: "\n> ")
  }

  public func contextualizing(_ body: String) -> String { context + "\n\n" + body }

  public static func splitContext(_ text: String) -> (quote: String, body: String)? {
    guard text.hasPrefix("> "), let separator = text.range(of: "\n\n") else { return nil }
    let lines = text[..<separator.lowerBound].components(separatedBy: "\n")
    guard lines.allSatisfy({ $0.hasPrefix("> ") }) else { return nil }
    return (
      lines.map { String($0.dropFirst(2)) }.joined(separator: "\n"),
      String(text[separator.upperBound...])
    )
  }
}
