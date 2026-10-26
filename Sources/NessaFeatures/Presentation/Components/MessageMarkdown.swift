import NessaDesignSystem
import SwiftUI

/// An agent reply drawn as markdown blocks: headings, lists, code, quotes, rules and tables,
/// each keeping its inline styles.
struct MessageMarkdown: View {
  let blocks: [MarkdownBlock]

  init(_ text: String) { blocks = MarkdownBlocks.parse(text) }

  var body: some View {
    VStack(alignment: .leading, spacing: MessagesStyle.markdownBlockSpacing) {
      ForEach(blocks) { block in
        MarkdownBlockView(block: block)
      }
    }
  }
}

private struct MarkdownBlockView: View {
  let block: MarkdownBlock

  var body: some View {
    switch block.kind {
    case .heading(let level):
      Text(block.text).font(MessagesStyle.markdownHeading(level))
    case .paragraph:
      Text(block.text)
    case .listItem(let ordinal, let depth):
      HStack(alignment: .firstTextBaseline, spacing: MessagesStyle.markdownMarkerGap) {
        Text(ordinal.map { "\($0)." } ?? (depth > 1 ? "◦" : "•"))
          .monospacedDigit()
          .foregroundStyle(MessagesStyle.secondary)
        Text(block.text).frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.leading, CGFloat(depth - 1) * MessagesStyle.markdownListIndent)
    case .code:
      ScrollView(.horizontal, showsIndicators: false) {
        Text(block.text).font(MessagesStyle.markdownCode).fixedSize()
          .padding(MessagesStyle.markdownCodeInset)
      }
      .background(
        MessagesStyle.markdownCodeFill,
        in: RoundedRectangle(cornerRadius: MessagesStyle.markdownCodeRadius))
    case .quote:
      HStack(spacing: MessagesStyle.markdownMarkerGap) {
        Capsule().fill(MessagesStyle.secondary).frame(width: MessagesStyle.markdownQuoteBar)
        Text(block.text).foregroundStyle(MessagesStyle.secondary)
      }
      .fixedSize(horizontal: false, vertical: true)
    case .rule:
      Rectangle().fill(MessagesStyle.separator).frame(height: MessagesStyle.markdownRule)
    case .tableRow(let header):
      ScrollView(.horizontal, showsIndicators: false) {
        Text(block.text).font(MessagesStyle.markdownCode)
          .fontWeight(header ? .semibold : .regular).fixedSize()
      }
    }
  }
}
