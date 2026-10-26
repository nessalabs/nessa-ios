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

@Test func aTableBecomesOneRowPerLineWithItsCellsSeparated() {
  let markdown = "| a | b |\n|---|---|\n| 1 | 2 |"
  #expect(kinds(markdown) == [.tableRow(header: true), .tableRow(header: false)])
  #expect(texts(markdown) == [
    "a\(MarkdownBlocks.cellSeparator)b", "1\(MarkdownBlocks.cellSeparator)2",
  ])
}

@Test func plainAndMalformedTextStillReads() {
  #expect(texts("just words") == ["just words"])
  #expect(kinds("**never closed and `open") == [.paragraph])
  #expect(texts("**never closed and `open").first?.contains("never closed") == true)
  #expect(MarkdownBlocks.parse("").isEmpty)
}
