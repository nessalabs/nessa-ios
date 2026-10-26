import SwiftUI

/// A channel as a card: a lettered tile above its name, and a dot while one of its chats is
/// unread.
public struct NessaChannelCard: View {
  private let name: String
  private let unread: Bool
  private let action: () -> Void

  public init(name: String, unread: Bool = false, action: @escaping () -> Void) {
    self.name = name
    self.unread = unread
    self.action = action
  }

  public var body: some View {
    let card = RoundedRectangle(cornerRadius: MessagesStyle.channelCardRadius, style: .continuous)
    let tile = RoundedRectangle(cornerRadius: MessagesStyle.channelTileRadius, style: .continuous)
    Button(action: action) {
      VStack(alignment: .leading, spacing: 0) {
        HStack(alignment: .top) {
          Text(Self.initial(name)).font(MessagesStyle.channelInitial)
            .frame(width: MessagesStyle.channelTile, height: MessagesStyle.channelTile)
            .background(MessagesStyle.channelTileFill, in: tile)
            .overlay(tile.strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
          Spacer(minLength: 0)
          if unread {
            Circle().fill(NessaColor.accent)
              .frame(width: MessagesStyle.statusDot, height: MessagesStyle.statusDot)
          }
        }
        Spacer(minLength: 0)
        Text(name).font(MessagesStyle.channelName).lineLimit(1).truncationMode(.tail)
      }
      .foregroundStyle(MessagesStyle.foreground)
      .padding(NessaSpacing.sm)
      .frame(maxWidth: .infinity, minHeight: MessagesStyle.channelCardHeight, alignment: .leading)
      .background(MessagesStyle.channelCardFill, in: card)
      .overlay(card.strokeBorder(NessaColor.hairline, lineWidth: 0.5))
      .contentShape(card)
    }
    .buttonStyle(.nessaPress)
    .accessibilityLabel(unread ? "\(name), unread" : name)
  }

  /// The name's first letter or digit, so "nessa-agent" and "#ops" still read as one glyph.
  static func initial(_ name: String) -> String {
    guard let first = name.first(where: { $0.isLetter || $0.isNumber }) else { return "·" }
    return String(first).uppercased()
  }
}
