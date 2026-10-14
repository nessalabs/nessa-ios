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
  public init(hex: UInt, opacity: Double = 1) {
    self.init(
      .sRGB, red: Double((hex >> 16) & 255) / 255,
      green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: opacity)
  }
}

/// The Nessa dark theme, converted from nessa_ui's `theme.css` (`.dark`) to sRGB.
/// The neutrals are its shadcn ramp; the accent is the fixed chat identity.
public enum NessaColor {
  /// `--background`, oklch(0.145 0 0).
  public static let background = Color(hex: 0x0A0A0A)
  /// `--card`, oklch(0.205 0 0): a raised surface such as an incoming bubble.
  public static let card = Color(hex: 0x171717)
  /// `--muted`, oklch(0.269 0 0): a control at rest.
  public static let muted = Color(hex: 0x262626)
  /// `--foreground`, oklch(0.985 0 0).
  public static let foreground = Color(hex: 0xFAFAFA)
  /// `--muted-foreground`, oklch(0.708 0 0): secondary text.
  public static let mutedForeground = Color(hex: 0xA1A1A1)
  /// A hairline drawn on top of a surface, as the foreground's ink.
  public static let hairline = Color.white.opacity(0.08)
  /// `--nessa-chat-accent`: the sent bubble, the live dot, the send button.
  public static let accent = Color(hex: 0x0071E3)
  /// A deeper step of the accent, for the foot of the sent bubble's gradient.
  public static let accentDeep = Color(hex: 0x0058C4)
  /// `--nessa-chat-accent-ink` (dark): the accent as text or an icon.
  public static let accentInk = Color(hex: 0x5AAAFF)
  /// `--destructive` (dark), oklch(0.704 0.187 22.216).
  public static let destructive = Color(hex: 0xFF6668)

  /// The `--nessa-chat-rim-*` stops: amber through pink and purple into cyan, then the
  /// near-white head. A light source, identical in both themes.
  public static let rim: [Color] = [
    Color(hex: 0xF59E0B, opacity: 0.06), Color(hex: 0xF59E0B, opacity: 0.22),
    Color(hex: 0xEC4899, opacity: 0.42), Color(hex: 0xA855F7, opacity: 0.62),
    Color(hex: 0x38BDF8, opacity: 0.85), .white,
  ]

  /// The agent hue wheel (`AGENT_HUES`), in degrees.
  public static let agentHues: [Double] = [25, 195, 300, 340]
}

/// nessa_ui's motion tokens (`--nessa-motion-*`) plus the springs the phone uses for touch.
public enum NessaMotion {
  public static let normal: Double = 0.2
  public static let slow: Double = 0.3
  /// One revolution of an ambient effect such as the composer rim.
  public static let ambient: Double = 3.2

  /// `--nessa-motion-easing-standard`, cubic-bezier(0.2, 0, 0, 1).
  public static func standard(_ duration: Double = normal) -> Animation {
    .timingCurve(0.2, 0, 0, 1, duration: duration)
  }
  /// `--nessa-motion-easing-emphasized`, cubic-bezier(0.4, 0, 0.2, 1).
  public static func emphasized(_ duration: Double = slow) -> Animation {
    .timingCurve(0.4, 0, 0.2, 1, duration: duration)
  }

  /// A finger going down and coming back up: quick, with a little give.
  public static let press = Animation.spring(duration: 0.24, bounce: 0.3)
  /// Something arriving on screen.
  public static let enter = Animation.spring(duration: 0.42, bounce: 0.18)
  /// Something changing shape or swapping in place.
  public static let morph = Animation.spring(duration: 0.34, bounce: 0.22)
  /// How far a pressed control sinks.
  public static let pressScale: CGFloat = 0.94
  /// How far a disabled control dims.
  public static let disabledOpacity: Double = 0.45
  /// How far a pressed control dims.
  public static let pressOpacity: Double = 0.82
  /// `nessa-enter`: an entering element starts this much smaller.
  public static let enterScale: CGFloat = 0.96
}
