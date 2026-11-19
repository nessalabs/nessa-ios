import SwiftUI

/// A table of styled text on a quiet panel, matching the desktop's markdown tables: a header
/// band of smaller column names, a first column a step stronger, rules between rows and
/// fainter ones between columns. Each column is as wide as its widest cell, up to
/// `MessagesStyle.tableColumnMax`, past which its text wraps. A table that fits hugs its
/// columns; one that does not scrolls sideways inside its panel and fades the side with
/// columns past it, rather than pushing the message wider.
public struct MessagesTextTable: View {
  public let alignments: [TextAlignment]
  /// Empty when the table has no header row.
  public let header: [AttributedString]
  public let rows: [[AttributedString]]

  public init(alignments: [TextAlignment], header: [AttributedString], rows: [[AttributedString]]) {
    self.alignments = alignments
    self.header = header
    self.rows = rows
  }

  public var body: some View {
    ViewThatFits(in: .horizontal) {
      grid
      FadingSidewaysScroll { grid }
    }
    .background(MessagesStyle.tableFill)
    .clipShape(RoundedRectangle(cornerRadius: MessagesStyle.tableRadius))
    .overlay {
      RoundedRectangle(cornerRadius: MessagesStyle.tableRadius)
        .strokeBorder(MessagesStyle.tableEdge, lineWidth: MessagesStyle.tableHairline)
    }
  }

  private var columns: Int { alignments.count }
  private var allRows: [[AttributedString]] { header.isEmpty ? rows : [header] + rows }

  private var grid: some View {
    let table = allRows
    let rowCount = table.count
    return TableGridLayout(columns: columns, rows: rowCount) {
      ForEach(0..<(rowCount * columns), id: \.self) { index in
        cell(table, row: index / columns, column: index % columns)
      }
      ForEach(0..<max(0, columns - 1), id: \.self) { _ in
        Rectangle().fill(MessagesStyle.tableColumnRule)
      }
      ForEach(0..<max(0, rowCount - 1), id: \.self) { _ in
        Rectangle().fill(MessagesStyle.tableRowRule)
      }
    }
  }

  private func cell(_ table: [[AttributedString]], row: Int, column: Int) -> some View {
    let isHeader = row == 0 && !header.isEmpty
    let alignment = alignments[column]
    let text = column < table[row].count ? table[row][column] : AttributedString()
    return Text(text)
      .font(
        isHeader
          ? MessagesStyle.tableHeader
          : column == 0 ? MessagesStyle.tableFirstColumn : MessagesStyle.tableText
      )
      .foregroundStyle(isHeader ? MessagesStyle.secondary : MessagesStyle.foreground)
      .monospacedDigit()
      .multilineTextAlignment(alignment)
      .padding(.horizontal, MessagesStyle.tableCellHorizontal)
      .padding(.vertical, MessagesStyle.tableCellVertical)
      .frame(
        maxWidth: .infinity, maxHeight: .infinity,
        alignment: Alignment(horizontal: alignment.horizontal, vertical: .center)
      )
      .background(isHeader ? MessagesStyle.tableHeaderFill : .clear)
  }
}

extension TextAlignment {
  fileprivate var horizontal: HorizontalAlignment {
    switch self {
    case .leading: .leading
    case .center: .center
    case .trailing: .trailing
    }
  }
}

/// Lays cells out row by row, then the rules between columns, then the rules between rows.
/// A column takes its widest cell's single-line width, capped so long text wraps; a row takes
/// its tallest cell at those widths. The grid keeps that natural size whatever it is offered.
private struct TableGridLayout: Layout {
  let columns: Int
  let rows: Int

  struct Cache {
    var widths: [CGFloat] = []
    var heights: [CGFloat] = []
  }

  func makeCache(subviews: Subviews) -> Cache { measure(subviews) }

  func updateCache(_ cache: inout Cache, subviews: Subviews) { cache = measure(subviews) }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
    CGSize(width: cache.widths.reduce(0, +), height: cache.heights.reduce(0, +))
  }

  func placeSubviews(
    in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache
  ) {
    guard columns > 0, rows > 0, subviews.count >= rows * columns else { return }
    let size = sizeThatFits(proposal: proposal, subviews: subviews, cache: &cache)
    let rule = MessagesStyle.tableHairline
    var y = bounds.minY
    for row in 0..<rows {
      var x = bounds.minX
      for column in 0..<columns {
        let width = cache.widths[column]
        let height = cache.heights[row]
        subviews[row * columns + column].place(
          at: CGPoint(x: x, y: y), anchor: .topLeading,
          proposal: ProposedViewSize(width: width, height: height))
        x += width
      }
      y += cache.heights[row]
    }
    var index = rows * columns
    var x = bounds.minX
    for column in 0..<(columns - 1) where index < subviews.count {
      x += cache.widths[column]
      subviews[index].place(
        at: CGPoint(x: x - rule / 2, y: bounds.minY), anchor: .topLeading,
        proposal: ProposedViewSize(width: rule, height: size.height))
      index += 1
    }
    y = bounds.minY
    for row in 0..<(rows - 1) where index < subviews.count {
      y += cache.heights[row]
      subviews[index].place(
        at: CGPoint(x: bounds.minX, y: y - rule / 2), anchor: .topLeading,
        proposal: ProposedViewSize(width: size.width, height: rule))
      index += 1
    }
  }

  private func measure(_ subviews: Subviews) -> Cache {
    guard columns > 0, rows > 0, subviews.count >= rows * columns else { return Cache() }
    var widths = [CGFloat](repeating: 0, count: columns)
    for row in 0..<rows {
      for column in 0..<columns {
        let ideal = subviews[row * columns + column].sizeThatFits(.unspecified).width
        widths[column] = max(widths[column], min(ideal, MessagesStyle.tableColumnMax))
      }
    }
    widths = widths.map { $0.rounded(.up) }
    var heights = [CGFloat](repeating: 0, count: rows)
    for row in 0..<rows {
      for column in 0..<columns {
        let fitted = subviews[row * columns + column].sizeThatFits(
          ProposedViewSize(width: widths[column], height: nil))
        heights[row] = max(heights[row], fitted.height.rounded(.up))
      }
    }
    return Cache(widths: widths, heights: heights)
  }
}

/// A sideways scroll that fades whichever side has content past it.
private struct FadingSidewaysScroll<Content: View>: View {
  @ViewBuilder let content: Content
  @State private var hidden = HiddenSides()

  struct HiddenSides: Equatable {
    var leading = false
    var trailing = false
  }

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) { content }
      .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
      .onScrollGeometryChange(for: HiddenSides.self) { geometry in
        let offset = geometry.contentOffset.x + geometry.contentInsets.leading
        let visible = geometry.containerSize.width
        return HiddenSides(
          leading: offset > 1, trailing: offset + visible < geometry.contentSize.width - 1)
      } action: { _, sides in
        hidden = sides
      }
      .mask {
        HStack(spacing: 0) {
          LinearGradient(
            colors: [.black.opacity(hidden.leading ? 0 : 1), .black],
            startPoint: .leading, endPoint: .trailing
          )
          .frame(width: MessagesStyle.tableEdgeFade)
          Rectangle()
          LinearGradient(
            colors: [.black, .black.opacity(hidden.trailing ? 0 : 1)],
            startPoint: .leading, endPoint: .trailing
          )
          .frame(width: MessagesStyle.tableEdgeFade)
        }
      }
  }
}

#Preview("Markdown table") {
  VStack(alignment: .leading, spacing: 24) {
    MessagesTextTable(
      alignments: [.leading, .trailing],
      header: ["Plan", "Price"],
      rows: [["Free", "$0"], ["Pro", "$20"]])
    MessagesTextTable(
      alignments: [.leading, .leading, .center, .trailing],
      header: ["Film", "Venue", "Date", "Seats"],
      rows: [
        ["A long film title that wraps over two lines", "Grand Lake Theater", "Fri 21", "212"],
        ["Short", "Roxie", "Sat 22", "9"],
      ])
  }
  .padding()
  .background(MessagesStyle.background)
}
