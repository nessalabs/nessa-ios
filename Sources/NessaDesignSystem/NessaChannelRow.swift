import SwiftUI

/// A channel in the sidebar: its lit tile, its name in the sidebar's serif, and a dot while
/// one of its chats is unread.
public struct NessaChannelRow: View {
  private let name: String
  private let position: Int
  private let unread: Bool
  private let action: () -> Void

  /// `position` is the row's place in the list, which picks its tile's light.
  public init(
    name: String, position: Int, unread: Bool = false, action: @escaping () -> Void
  ) {
    self.name = name
    self.position = position
    self.unread = unread
    self.action = action
  }

  public var body: some View {
    Button(action: action) {
      HStack(spacing: NessaSpacing.sm) {
        NessaChannelTile(name: name, position: position)
        Text(name).font(MessagesStyle.channelName).lineLimit(1).truncationMode(.tail)
        Spacer(minLength: 0)
        if unread {
          Circle().fill(NessaColor.accent)
            .frame(width: MessagesStyle.statusDot, height: MessagesStyle.statusDot)
        }
      }
      .foregroundStyle(MessagesStyle.foreground)
      .padding(.horizontal, NessaSpacing.sm)
      .frame(height: MessagesStyle.channelRowHeight)
      .contentShape(Rectangle())
    }
    .buttonStyle(.nessaPress)
    .accessibilityLabel(unread ? "\(name), unread" : name)
  }
}

/// A channel's tile: the home screen's light, in the same halftone, under the name's first
/// letter. The light falls from a side the tile's place in the list picks, so neighbours are
/// always lit differently and the tiles tell channels apart without a colour.
public struct NessaChannelTile: View {
  private let name: String
  private let position: Int
  public init(name: String, position: Int) {
    self.name = name
    self.position = position
  }

  public var body: some View {
    let tile = RoundedRectangle(cornerRadius: MessagesStyle.channelTileRadius, style: .continuous)
    let sources = ChannelTileStyle.sources
    let source = sources[((position % sources.count) + sources.count) % sources.count]
    Canvas { context, size in
      context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
      let centre = CGPoint(x: source.x * size.width, y: source.y * size.height)
      let reach = size.width * ChannelTileStyle.reach
      let cell = ChannelTileStyle.cell
      var dots = Path()
      var y: CGFloat = 0
      while y < size.height {
        var x: CGFloat = 0
        while x < size.width {
          let d = max(0, 1 - hypot(x + cell / 2 - centre.x, y + cell / 2 - centre.y) / reach)
          // As on the home screen: the dot's area follows the light, and specks are left out.
          let diameter = cell * 0.95 * d.squareRoot()
          if diameter > ChannelTileStyle.smallestDot {
            dots.addEllipse(
              in: CGRect(
                x: x + (cell - diameter) / 2, y: y + (cell - diameter) / 2, width: diameter,
                height: diameter))
          }
          x += cell
        }
        y += cell
      }
      context.fill(dots, with: .color(MessagesStyle.channelLight))
    }
    .overlay {
      Text(Self.initial(name)).font(MessagesStyle.channelInitial)
        .foregroundStyle(MessagesStyle.foreground)
        .shadow(color: .black.opacity(0.9), radius: 3)
    }
    .frame(width: MessagesStyle.channelTile, height: MessagesStyle.channelTile)
    .clipShape(tile)
    .overlay(tile.strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
    .accessibilityHidden(true)
  }

  /// The name's first letter or digit, so "nessa-agent" and "#ops" still read as one glyph.
  static func initial(_ name: String) -> String {
    guard let first = name.first(where: { $0.isLetter || $0.isNumber }) else { return "·" }
    return String(first).uppercased()
  }
}

enum ChannelTileStyle {
  static let cell: CGFloat = 3
  static let smallestDot: CGFloat = 0.7
  /// How far the light carries, as a share of the tile's width.
  static let reach: CGFloat = 1.15
  /// Where the light comes from, in the tile's unit square: four sides, just off its edges.
  static let sources: [CGPoint] = [
    CGPoint(x: 0.5, y: 1.25), CGPoint(x: -0.15, y: -0.15), CGPoint(x: 1.25, y: 0.5),
    CGPoint(x: 0.5, y: -0.25),
  ]
}
