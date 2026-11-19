import Foundation

/// One block of an agent's markdown reply, with its inline styles (bold, italic, code,
/// links) kept on `text`.
struct MarkdownBlock: Equatable, Identifiable {
  enum Kind: Equatable {
    case heading(level: Int)
    case paragraph
    /// `ordinal` is nil in an unordered list; `depth` counts from 1 at the outermost list.
    case listItem(ordinal: Int?, depth: Int)
    case code(language: String?)
    case quote
    case rule
    /// One table row, drawn as monospaced text with its cells separated.
    case tableRow(header: Bool)
  }
  let id: Int
  let kind: Kind
  let text: AttributedString
}

/// Splits markdown into blocks by each run's presentation intent. Input the parser cannot
/// read at all comes back as one plain paragraph, so a reply is never lost.
enum MarkdownBlocks {
  static let cellSeparator = "  │  "

  static func parse(_ markdown: String) -> [MarkdownBlock] {
    let options = AttributedString.MarkdownParsingOptions(
      interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible)
    guard let parsed = try? AttributedString(markdown: markdown, options: options) else {
      return plain(markdown)
    }
    var blocks: [MarkdownBlock] = []
    var current: (key: Int, kind: MarkdownBlock.Kind, text: AttributedString, cell: Int?)?
    func close() {
      guard let open = current else { return }
      var text = open.text
      if case .code = open.kind { text = trimmingTrailingNewlines(text) }
      if !text.characters.isEmpty || open.kind == .rule {
        blocks.append(MarkdownBlock(id: blocks.count, kind: open.kind, text: text))
      }
      current = nil
    }
    for run in parsed.runs {
      let intent = run.presentationIntent
      let key = blockKey(intent)
      let kind = blockKind(intent)
      var piece = AttributedString(parsed[run.range])
      piece.presentationIntent = nil
      let cell = cellIndex(intent)
      if let open = current, open.key == key {
        if let cell, cell != open.cell {
          current?.text.append(AttributedString(cellSeparator))
        }
        current?.text.append(piece)
        current?.cell = cell
      } else {
        close()
        current = (key, kind, piece, cell)
      }
    }
    close()
    return blocks.isEmpty ? plain(markdown) : blocks
  }

  private static func plain(_ text: String) -> [MarkdownBlock] {
    text.isEmpty ? [] : [MarkdownBlock(id: 0, kind: .paragraph, text: AttributedString(text))]
  }

  /// Runs belong to one block while they share its innermost component, except that a
  /// table row's cells are one block.
  private static func blockKey(_ intent: PresentationIntent?) -> Int {
    guard let components = intent?.components, let first = components.first else { return -1 }
    if case .tableCell = first.kind, components.count > 1 { return components[1].identity }
    return first.identity
  }

  private static func cellIndex(_ intent: PresentationIntent?) -> Int? {
    guard let first = intent?.components.first, case .tableCell(let column) = first.kind
    else { return nil }
    return column
  }

  private static func blockKind(_ intent: PresentationIntent?) -> MarkdownBlock.Kind {
    guard let components = intent?.components else { return .paragraph }
    var ordinal: Int?
    var inItem = false
    var lists: [Bool] = []
    var quoted = false
    for component in components {
      switch component.kind {
      case .listItem(let value):
        if !inItem { ordinal = value }
        inItem = true
      case .orderedList: lists.append(true)
      case .unorderedList: lists.append(false)
      case .blockQuote: quoted = true
      default: break
      }
    }
    switch components.first?.kind {
    case .header(let level): return .heading(level: min(max(level, 1), 6))
    case .codeBlock(let language): return .code(language: language)
    case .thematicBreak: return .rule
    case .tableCell:
      return .tableRow(header: components.contains { $0.kind == .tableHeaderRow })
    default: break
    }
    if inItem, let innermostList = lists.first {
      return .listItem(ordinal: innermostList ? ordinal : nil, depth: lists.count)
    }
    return quoted ? .quote : .paragraph
  }

  private static func trimmingTrailingNewlines(_ text: AttributedString) -> AttributedString {
    var text = text
    while let last = text.characters.last, last.isNewline {
      text.removeSubrange(text.index(beforeCharacter: text.endIndex)..<text.endIndex)
    }
    return text
  }
}
