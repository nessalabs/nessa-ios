import SwiftUI

public struct MessagesJumpToLatest: View {
  private let action: () -> Void
  public init(action: @escaping () -> Void) { self.action = action }

  public var body: some View {
    Button(action: action) {
      Image(systemName: "arrow.down")
        .font(MessagesStyle.jumpToLatestIcon)
        .foregroundStyle(MessagesStyle.foreground)
        .frame(width: MessagesStyle.jumpToLatestSize, height: MessagesStyle.jumpToLatestSize)
        .messagesGlass()
        .frame(width: MessagesStyle.controlHeight, height: MessagesStyle.controlHeight)
        .contentShape(Rectangle())
    }
    .buttonStyle(.nessaPress)
    .accessibilityLabel("Jump to latest messages")
  }
}
