import SwiftUI

/// A second tap, asked where the first one happened: a small capsule in the action's tint
/// that grows out of the edge of the row it confirms. A one-tap action on one item (a
/// swipe's Delete, a menu's Archive) turns into this rather than a sheet or an alert.
public struct NessaInlineConfirm: View {
  private let title: String
  private let symbol: String
  private let tint: Color
  private let action: () -> Void
  public init(_ title: String, symbol: String, tint: Color, action: @escaping () -> Void) {
    self.title = title
    self.symbol = symbol
    self.tint = tint
    self.action = action
  }
  public var body: some View {
    Button(action: action) {
      Label(title, systemImage: symbol).font(ConfirmStyle.label)
        .foregroundStyle(NessaColor.foreground)
        .padding(.horizontal, NessaSpacing.md)
        .frame(height: ConfirmStyle.height)
        .background(tint, in: Capsule())
    }
    .buttonStyle(.nessaPress)
    .transition(.scale(scale: ConfirmStyle.enterScale, anchor: .trailing).combined(with: .opacity))
  }
}

private enum ConfirmStyle {
  static let label = Font.system(size: 15, weight: .semibold)
  static let height: CGFloat = 36
  static let enterScale: CGFloat = 0.6
}
