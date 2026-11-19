import Foundation
import Testing

@testable import NessaFeatures

private func kinds(_ markdown: String) -> [MarkdownBlock.Kind] {
  MarkdownBlocks.parse(markdown).map(\.kind)
}

private func texts(_ markdown: String) -> [String] {
  MarkdownBlocks.parse(markdown).map { String($0.text.characters) }
}

@Test func headingsKeepTheirLevelAndText() {
  let markdown = "# One\n\n## Two\n\n### Useful AI projects\n\n###### Six"
  #expect(kinds(markdown) == [
    .heading(level: 1), .heading(level: 2), .heading(level: 3), .heading(level: 6),
  ])
  #expect(texts(markdown) == ["One", "Two", "Useful AI projects", "Six"])
}

@Test func unorderedListsNestAndOrderedListsCount() {
  let markdown = """
    - first
    - second
      - inner
    1. one
    2. two
    """
  #expect(kinds(markdown) == [
    .listItem(ordinal: nil, depth: 1), .listItem(ordinal: nil, depth: 1),
    .listItem(ordinal: nil, depth: 2), .listItem(ordinal: 1, depth: 1),
    .listItem(ordinal: 2, depth: 1),
  ])
  #expect(texts(markdown) == ["first", "second", "inner", "one", "two"])
}

@Test func anOrderedListInsideABulletKeepsItsNumbers() {
  let markdown = "- outer\n  1. a\n  2. b"
  #expect(kinds(markdown) == [
    .listItem(ordinal: nil, depth: 1), .listItem(ordinal: 1, depth: 2),
    .listItem(ordinal: 2, depth: 2),
  ])
}

@Test func aFencedCodeBlockKeepsItsLanguageAndLinesWithoutTheTrailingNewline() {
  let markdown = "Run:\n\n```swift\nlet a = 1\nprint(a)\n```"
  #expect(kinds(markdown) == [.paragraph, .code(language: "swift")])
  #expect(texts(markdown) == ["Run:", "let a = 1\nprint(a)"])
}

@Test func aQuoteAndARuleAreTheirOwnBlocks() {
  let markdown = "> quoted words\n\n---\n\nafter"
  #expect(kinds(markdown) == [.quote, .rule, .paragraph])
  #expect(texts(markdown).first == "quoted words")
}

@Test func inlineStylesStayInsideTheirBlock() throws {
  let blocks = MarkdownBlocks.parse("- **bold** and *it* and `code` and [link](https://nessa.app)")
  #expect(blocks.count == 1)
  let text = try #require(blocks.first?.text)
  #expect(String(text.characters) == "bold and it and code and link")
  let intents = text.runs.compactMap(\.inlinePresentationIntent)
  #expect(intents.contains(.stronglyEmphasized))
  #expect(intents.contains(.emphasized))
  #expect(intents.contains(.code))
  #expect(text.runs.contains { $0.link == URL(string: "https://nessa.app") })
  #expect(text.runs.allSatisfy { $0.presentationIntent == nil })
}

private func cells(_ row: [AttributedString]) -> [String] { row.map { String($0.characters) } }

private func onlyTable(_ markdown: String) throws -> MarkdownTable {
  let blocks = MarkdownBlocks.parse(markdown)
  try #require(blocks.count == 1)
  guard case .table(let table) = blocks[0].kind else {
    Issue.record("expected a table, got \(blocks[0].kind)")
    throw CancellationError()
  }
  return table
}

@Test func aTableKeepsItsHeaderRowsAndColumnAlignment() throws {
  let table = try onlyTable("| Name | Qty | Note |\n|:---|---:|:---:|\n| apple | 2 | ripe |\n| pear | 10 | ok |")
  #expect(cells(table.header) == ["Name", "Qty", "Note"])
  #expect(table.rows.map(cells) == [["apple", "2", "ripe"], ["pear", "10", "ok"]])
  #expect(table.alignments == [.leading, .trailing, .center])
}

@Test func anEmptyCellStaysInItsColumn() throws {
  let table = try onlyTable("| a | b | c |\n|---|---|---|\n| 1 |  | 3 |\n|  | 2 |  |")
  #expect(table.rows.map(cells) == [["1", "", "3"], ["", "2", ""]])
}

@Test func aTableCellKeepsItsInlineStyles() throws {
  let table = try onlyTable("| k | v |\n|---|---|\n| **bold** and `code` | [site](https://nessa.app) |")
  let first = table.rows[0][0]
  #expect(String(first.characters) == "bold and code")
  #expect(first.runs.contains { $0.inlinePresentationIntent == .stronglyEmphasized })
  #expect(first.runs.contains { $0.inlinePresentationIntent == .code })
  #expect(table.rows[0][1].runs.contains { $0.link == URL(string: "https://nessa.app") })
  #expect(first.runs.allSatisfy { $0.presentationIntent == nil })
}

@Test func blocksAroundATableAndTwoTablesInARowStayApart() {
  let markdown = """
    Before

    | a | b |
    |---|---|
    | 1 | 2 |

    Between

    | c |
    |---|
    | 3 |

    After
    """
  let blocks = MarkdownBlocks.parse(markdown)
  #expect(blocks.count == 5)
  #expect(texts(markdown) == ["Before", "a\tb\n1\t2", "Between", "c\n3", "After"])
}

@Test func taskItemsShowTheirBoxAndKeepTheirText() {
  let markdown = "- [ ] open\n- [x] done\n- plain"
  #expect(kinds(markdown) == [
    .task(done: false, depth: 1), .task(done: true, depth: 1), .listItem(ordinal: nil, depth: 1),
  ])
  #expect(texts(markdown) == ["open", "done", "plain"])
}

@Test func plainAndMalformedTextStillReads() {
  #expect(texts("just words") == ["just words"])
  #expect(kinds("**never closed and `open") == [.paragraph])
  #expect(texts("**never closed and `open").first?.contains("never closed") == true)
  #expect(MarkdownBlocks.parse("").isEmpty)
}
