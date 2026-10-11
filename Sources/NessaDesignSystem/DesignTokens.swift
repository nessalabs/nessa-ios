import SwiftUI

public enum NessaSpacing {
  public static let xxs: CGFloat = 4
  public static let xs: CGFloat = 8
  public static let sm: CGFloat = 12
  public static let md: CGFloat = 16
  public static let lg: CGFloat = 22
  public static let xl: CGFloat = 32
}
public enum NessaRadius { public static let xl: CGFloat = 22 }
public enum NessaType { public static let mono = Font.system(size: 13, design: .monospaced) }
extension Color {
  public init(hex: UInt) {
    self.init(
      .sRGB, red: Double((hex >> 16) & 255) / 255,
      green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
  }
}
