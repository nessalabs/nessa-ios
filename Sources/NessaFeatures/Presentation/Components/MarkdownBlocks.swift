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
    /// A whole table; `text` holds its cells as plain text, a tab between cells.
    case table(MarkdownTable)
  }
  let id: Int
  let kind: Kind
  let text: AttributedString
}

/// A table's cells, each keeping its inline styles. Every row has one cell per column; a
/// cell left empty in the source is an empty string.
struct MarkdownTable: Equatable {
  enum Alignment: Equatable { case leading, center, trailing }
  let alignments: [Alignment]
  /// Empty when the table has no header row.
  let header: [AttributedString]
  let rows: [[AttributedString]]
}

/// Splits markdown into blocks by each run's presentation intent. Input the parser cannot
/// read at all comes back as one plain paragraph, so a reply is never lost.
enum MarkdownBlocks {
  static func parse(_ markdown: String) -> [MarkdownBlock] {
    let options = AttributedString.MarkdownParsingOptions(
      interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible)
    guard let parsed = try? AttributedString(markdown: markdown, options: options) else {
      return plain(markdown)
    }
    var blocks: [MarkdownBlock] = []
    var current: (key: Int, kind: MarkdownBlock.Kind, text: AttributedString)?
    var table: TableBuilder?
    func close() {
      if let open = current {
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
      }
      if let built = table?.build() {
        blocks.append(
          MarkdownBlock(id: blocks.count, kind: .table(built), text: plainText(built)))
      }
      current = nil
      table = nil
    }
    for run in parsed.runs {
      let intent = run.presentationIntent
      var piece = AttributedString(parsed[run.range])
      piece.presentationIntent = nil
      if let place = TablePlace(intent) {
        if table?.key != place.table {
          close()
          table = TableBuilder(key: place.table, alignments: place.alignments)
        }
        table?.append(piece, at: place)
        continue
      }
      let key = intent?.components.first?.identity ?? -1
      if table == nil, let open = current, open.key == key {
        current?.text.append(piece)
      } else {
        close()
        current = (key, blockKind(intent), piece)
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
    let head = String(text.characters.prefix(4))
    switch head {
    case "[ ] ": return false
    case "[x] ", "[X] ": return true
    default: return nil
    }
  }

  private static func plainText(_ table: MarkdownTable) -> AttributedString {
    let lines = ([table.header] + table.rows).filter { !$0.isEmpty }.map { row in
      row.map { String($0.characters) }.joined(separator: "\t")
    }
    return AttributedString(lines.joined(separator: "\n"))
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

/// Where a run sits in a table: which table, which row, which column.
private struct TablePlace {
  let table: Int
  let alignments: [MarkdownTable.Alignment]
  let row: Int
  let header: Bool
  let column: Int

  init?(_ intent: PresentationIntent?) {
    var table: (Int, [MarkdownTable.Alignment])?
    var row: (Int, Bool)?
    var column: Int?
    for component in intent?.components ?? [] {
      switch component.kind {
      case .tableCell(let index): if column == nil { column = index }
      case .tableHeaderRow: if row == nil { row = (component.identity, true) }
      case .tableRow: if row == nil { row = (component.identity, false) }
      case .table(let columns):
        if table == nil {
          table = (component.identity, columns.map(MarkdownTable.Alignment.init))
        }
      default: break
      }
    }
    guard let table, let row, let column else { return nil }
    self.table = table.0
    alignments = table.1
    self.row = row.0
    header = row.1
    self.column = column
  }
}

private struct TableBuilder {
  let key: Int
  var alignments: [MarkdownTable.Alignment]
  var rows: [(id: Int, header: Bool, cells: [AttributedString])] = []

  init(key: Int, alignments: [MarkdownTable.Alignment]) {
    self.key = key
    self.alignments = alignments
  }

  mutating func append(_ piece: AttributedString, at place: TablePlace) {
    if rows.last?.id != place.row {
      rows.append((place.row, place.header, [AttributedString](repeating: "", count: alignments.count)))
    }
    while place.column >= alignments.count {
      alignments.append(.leading)
      for index in rows.indices { rows[index].cells.append("") }
    }
    rows[rows.count - 1].cells[place.column].append(piece)
  }

  func build() -> MarkdownTable {
    MarkdownTable(
      alignments: alignments,
      header: rows.first { $0.header }?.cells ?? [],
      rows: rows.filter { !$0.header }.map(\.cells))
  }
}

extension MarkdownTable.Alignment {
  fileprivate init(_ column: PresentationIntent.TableColumn) {
    switch column.alignment {
    case .center: self = .center
    case .right: self = .trailing
    default: self = .leading
    }
  }
}
