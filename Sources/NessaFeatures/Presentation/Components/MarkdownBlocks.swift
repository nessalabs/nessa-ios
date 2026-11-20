import Foundation

/// One block of an agent's markdown reply, with its inline styles (bold, italic, code,
/// links) kept on `text`.
struct MarkdownBlock: Equatable, Identifiable {
  enum Kind: Equatable {
    case heading(level: Int)
    case paragraph
    /// `ordinal` is nil in an unordered list; `depth` counts from 1 at the outermost list.
    case listItem(ordinal: Int?, depth: Int)
    /// A `- [ ]` or `- [x]` item; its text starts after the box.
    case task(done: Bool, depth: Int)
    case code(language: String?)
    case quote
    case rule
    /// A whole table: `rows` holds its cells, the first row its header when `header` is
    /// true. `columns` gives each column's alignment.
    case table(columns: [ColumnAlignment], header: Bool)
  }
  enum ColumnAlignment: Equatable { case leading, center, trailing }
  let id: Int
  let kind: Kind
  /// The block's text. A table's is its cells, one row per line, for copying and VoiceOver.
  let text: AttributedString
  /// A table's cells by row; empty for every other kind.
  var rows: [[AttributedString]] = []
}

/// Splits markdown into blocks by each run's presentation intent. Input the parser cannot
/// read at all comes back as one plain paragraph, so a reply is never lost.
enum MarkdownBlocks {
  /// What separates a table's cells in its plain `text`.
  static let cellSeparator = "\t"

  static func parse(_ markdown: String) -> [MarkdownBlock] {
    let options = AttributedString.MarkdownParsingOptions(
      interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible)
    guard let parsed = try? AttributedString(markdown: markdown, options: options) else {
      return plain(markdown)
    }
    var blocks: [MarkdownBlock] = []
    var current: (key: Int, kind: MarkdownBlock.Kind, text: AttributedString)?
    var table: Table?
    func closeTable() {
      guard let open = table else { return }
      table = nil
      let width = max(open.columns.count, open.rows.map(\.count).max() ?? 0)
      let rows = open.rows.map { $0 + Array(repeating: AttributedString(), count: width - $0.count) }
      guard !rows.isEmpty else { return }
      var columns = open.columns
      columns += Array(repeating: .leading, count: max(0, width - columns.count))
      var text = AttributedString()
      for (index, row) in rows.enumerated() {
        if index > 0 { text.append(AttributedString("\n")) }
        for (column, cell) in row.enumerated() {
          if column > 0 { text.append(AttributedString(cellSeparator)) }
          text.append(cell)
        }
      }
      blocks.append(
        MarkdownBlock(
          id: blocks.count, kind: .table(columns: columns, header: open.header), text: text,
          rows: rows))
    }
    func close() {
      closeTable()
      guard let open = current else { return }
      var text = open.text
      var kind = open.kind
      if case .code = kind { text = trimmingTrailingNewlines(text) }
      if case .listItem(_, let depth) = kind, let done = taskMark(text) {
        text.removeSubrange(text.startIndex..<text.index(text.startIndex, offsetByCharacters: 4))
        kind = .task(done: done, depth: depth)
      }
      if !text.characters.isEmpty || kind == .rule {
        blocks.append(MarkdownBlock(id: blocks.count, kind: kind, text: text))
      }
      current = nil
    }
    for run in parsed.runs {
      let intent = run.presentationIntent
      let key = blockKey(intent)
      let kind = blockKind(intent)
      var piece = AttributedString(parsed[run.range])
      piece.presentationIntent = nil
      if let place = tablePlace(intent) {
        if table?.key != place.table {
          close()
          table = Table(key: place.table, columns: place.columns, header: place.header)
        }
        if table?.rowKey != place.row {
          table?.rows.append([])
          table?.rowKey = place.row
        }
        let last = table!.rows.count - 1
        while table!.rows[last].count <= place.column { table?.rows[last].append(AttributedString()) }
        table?.rows[last][place.column].append(piece)
        continue
      }
      closeTable()
      if let open = current, open.key == key {
        current?.text.append(piece)
      } else {
        close()
        current = (key, kind, piece)
      }
    }
    close()
    return blocks.isEmpty ? plain(markdown) : blocks
  }

  private static func plain(_ text: String) -> [MarkdownBlock] {
    text.isEmpty ? [] : [MarkdownBlock(id: 0, kind: .paragraph, text: AttributedString(text))]
  }

  /// The box GitHub-flavored markdown puts at the start of a task item, which the system
  /// parser leaves as text: `[ ] ` is open, `[x] ` is done.
  private static func taskMark(_ text: AttributedString) -> Bool? {
    switch String(text.characters.prefix(4)) {
    case "[ ] ": return false
    case "[x] ", "[X] ": return true
    default: return nil
    }
  }

  /// A table being read: its cells so far, row by row.
  private struct Table {
    let key: Int
    let columns: [MarkdownBlock.ColumnAlignment]
    let header: Bool
    var rows: [[AttributedString]] = []
    var rowKey: Int?
  }

  /// Runs belong to one block while they share its innermost component.
  private static func blockKey(_ intent: PresentationIntent?) -> Int {
    intent?.components.first?.identity ?? -1
  }

  /// Where a table cell's run sits: its table, row and column, with the table's
  /// column alignments and whether it has a header row.
  private static func tablePlace(_ intent: PresentationIntent?) -> (
    table: Int, row: Int, column: Int, columns: [MarkdownBlock.ColumnAlignment], header: Bool
  )? {
    guard let components = intent?.components, let first = components.first,
      case .tableCell(let column) = first.kind, components.count > 1
    else { return nil }
    for component in components {
      if case .table(let alignments) = component.kind {
        let columns: [MarkdownBlock.ColumnAlignment] = alignments.map {
          switch $0.alignment {
          case .center: return .center
          case .right: return .trailing
          default: return .leading
          }
        }
        return (component.identity, components[1].identity, column, columns,
          components[1].kind == .tableHeaderRow)
      }
    }
    return nil
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
