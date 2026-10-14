import SwiftUI

public enum AgentDetailsStyle {
  public static let heroAvatar: CGFloat = 48
  public static let compactAvatar: CGFloat = 28
  public static let title = Font.system(size: 22, weight: .semibold)
  public static let subtitle = Font.system(size: 15)
  public static let chip = Font.system(size: 13, weight: .medium)
  public static let chipHeight: CGFloat = 28
  public static let sectionLabel = Font.system(size: 12, weight: .semibold)
  public static let sectionLabelTracking: CGFloat = 0.6
  public static let sectionIcon = Font.system(size: 13, weight: .semibold)
  public static let cardRadius: CGFloat = 20
  public static let tabHeight: CGFloat = 40
  public static let tabInset: CGFloat = 3
  public static let tabLabel = Font.system(size: 14, weight: .semibold)
  public static let collapseDistance: CGFloat = 56
  public static let collapsedScale: CGFloat = 0.92
  public static let timelineDot: CGFloat = 10
  public static let timelineGutter: CGFloat = 22
  public static let timelineLine: CGFloat = 1
  public static let statusPillHeight: CGFloat = 22
  public static let fileIcon: CGFloat = 40
  /// How far a tab's content rises as it swaps in.
  public static let tabSwapDistance: CGFloat = 10
}

/// A raised Nessa card: the card surface, a hairline edge, continuous corners.
public struct NessaCardSurface: ViewModifier {
  public func body(content: Content) -> some View {
    let shape = RoundedRectangle(cornerRadius: AgentDetailsStyle.cardRadius, style: .continuous)
    content.background(NessaColor.card, in: shape)
      .overlay(shape.strokeBorder(NessaColor.hairline, lineWidth: 0.5))
  }
}

/// A small capsule label: a model name, a status.
public struct NessaChip: View {
  private let text: String
  private let symbol: String?
  private let tint: Color
  public init(_ text: String, symbol: String? = nil, tint: Color = NessaColor.mutedForeground) {
    self.text = text
    self.symbol = symbol
    self.tint = tint
  }
  public var body: some View {
    HStack(spacing: NessaSpacing.xxs) {
      if let symbol { Image(systemName: symbol) }
      Text(text).lineLimit(1)
    }
    .font(AgentDetailsStyle.chip).foregroundStyle(tint)
    .padding(.horizontal, NessaSpacing.sm)
    .frame(height: AgentDetailsStyle.chipHeight)
    .background(tint.opacity(0.12), in: Capsule())
    .overlay(Capsule().strokeBorder(tint.opacity(0.22), lineWidth: 0.5))
  }
}

extension View {
  public func nessaCard() -> some View { modifier(NessaCardSurface()) }
}
