import NessaDesignSystem
import SwiftUI

/// An agent reply drawn as markdown blocks: headings, lists, task lists, code, quotes, rules
/// and tables, each keeping its inline styles.
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
    case .task(let done, let depth):
      HStack(alignment: .firstTextBaseline, spacing: MessagesStyle.markdownMarkerGap) {
        Image(systemName: done ? "checkmark.square" : "square")
          .font(MessagesStyle.markdownTaskBox)
          .foregroundStyle(MessagesStyle.secondary)
        Text(block.text)
          .foregroundStyle(done ? MessagesStyle.secondary : MessagesStyle.foreground)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.leading, CGFloat(depth - 1) * MessagesStyle.markdownListIndent)
      .accessibilityElement(children: .combine)
      .accessibilityValue(Text(done ? "done" : "not done"))
    case .code:
      MessageSideScroll {
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
    case .table(let columns, let header):
      MarkdownTable(rows: block.rows, columns: columns, header: header)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(block.text))
    }
  }
}

/// A markdown table as a grid: columns line up, the header row is set apart by a rule,
/// long cells wrap at a readable width, and a wide table scrolls sideways as one.
private struct MarkdownTable: View {
  let rows: [[AttributedString]]
  let columns: [MarkdownBlock.ColumnAlignment]
  let header: Bool

  var body: some View {
    MessageSideScroll {
      Grid(
        alignment: .topLeading, horizontalSpacing: MessagesStyle.markdownTableColumnGap,
        verticalSpacing: MessagesStyle.markdownTableRowGap
      ) {
        ForEach(rows.indices, id: \.self) { row in
          GridRow {
            ForEach(rows[row].indices, id: \.self) { column in
              Text(rows[row][column])
                .font(MessagesStyle.markdownTableText)
                .fontWeight(header && row == 0 ? .semibold : .regular)
                .multilineTextAlignment(textAlignment(column))
                .frame(maxWidth: MessagesStyle.markdownTableCellWidth, alignment: alignment(column))
                .fixedSize(horizontal: false, vertical: true)
                .gridColumnAlignment(horizontal(column))
            }
          }
          if row < rows.count - 1 {
            Rectangle()
              .fill(MessagesStyle.separator)
              .frame(height: MessagesStyle.markdownRule)
              .gridCellUnsizedAxes(.horizontal)
          }
        }
      }
      .padding(MessagesStyle.markdownCodeInset)
    }
    .background(
      MessagesStyle.markdownCodeFill,
      in: RoundedRectangle(cornerRadius: MessagesStyle.markdownCodeRadius))
  }

  private func at(_ column: Int) -> MarkdownBlock.ColumnAlignment {
    column < columns.count ? columns[column] : .leading
  }
  private func horizontal(_ column: Int) -> HorizontalAlignment {
    switch at(column) {
    case .leading: return .leading
    case .center: return .center
    case .trailing: return .trailing
    }
  }
  private func alignment(_ column: Int) -> Alignment {
    switch at(column) {
    case .leading: return .leading
    case .center: return .center
    case .trailing: return .trailing
    }
  }
  private func textAlignment(_ column: Int) -> TextAlignment {
    switch at(column) {
    case .leading: return .leading
    case .center: return .center
    case .trailing: return .trailing
    }
  }
}

/// Content wider than the bubble (code, a table) that scrolls sideways. In the held message's
/// preview, a still image that can't hold a scroll view, it shows its leading part clipped to the
/// bubble instead of a blank.
struct MessageSideScroll<Content: View>: View {
  @ViewBuilder let content: Content
  @Environment(\.messageSnapshot) private var snapshot

  var body: some View {
    if snapshot {
      content.frame(maxWidth: .infinity, alignment: .leading).clipped()
    } else {
      ScrollView(.horizontal, showsIndicators: false) { content }
    }
  }
}
