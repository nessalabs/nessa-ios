import SwiftUI

public enum ClawdiaTheme: String, CaseIterable, Sendable {
    case light
    case dark
}

public struct ClawdiaPalette: Sendable {
    public let background: Color
    public let surface: Color
    public let surface2: Color
    public let text: Color
    public let text2: Color
    public let text3: Color
    public let border: Color
    public let border2: Color
    public let accent: Color
    public let accent2: Color
    public let accentSoft: Color
    public let success: Color
    public let successSoft: Color
    public let warn: Color
    public let warnSoft: Color
    public let danger: Color
    public let dangerSoft: Color
    public let bubbleMeBackground: Color
    public let bubbleMeForeground: Color
    public let bubbleThemBackground: Color
    public let bubbleThemForeground: Color
    public let folders: [Color]
}

public enum ClawdiaColor {
    public static func palette(_ theme: ClawdiaTheme) -> ClawdiaPalette {
        switch theme {
        case .light:
            return ClawdiaPalette(
                background: Color(hex: 0xF6F3EC),
                surface: Color(hex: 0xFFFFFF),
                surface2: Color(hex: 0xFAF7F1),
                text: Color(hex: 0x1B1916),
                text2: Color(hex: 0x5C574F),
                text3: Color(hex: 0x94908A),
                border: Color(hex: 0xE9E4D9),
                border2: Color(hex: 0xDCD6C7),
                accent: Color(hex: 0x7B73E0),
                accent2: Color(hex: 0x5950C9),
                accentSoft: Color(hex: 0xECEAFA),
                success: Color(hex: 0x1F8A5B),
                successSoft: Color(hex: 0xDCEDE2),
                warn: Color(hex: 0xC9A26B),
                warnSoft: Color(hex: 0xF1E5CD),
                danger: Color(hex: 0xC25450),
                dangerSoft: Color(hex: 0xF4D9D7),
                bubbleMeBackground: Color(hex: 0x7B73E0),
                bubbleMeForeground: Color(hex: 0xFFFFFF),
                bubbleThemBackground: Color(hex: 0xFFFFFF),
                bubbleThemForeground: Color(hex: 0x1B1916),
                folders: [
                    Color(hex: 0xE8B69C), Color(hex: 0xB8C8B0), Color(hex: 0xC9A26B),
                    Color(hex: 0xA8B2C7), Color(hex: 0xD9B5C5), Color(hex: 0xB8A89C)
                ]
            )
        case .dark:
            return ClawdiaPalette(
                background: Color(hex: 0x0E0E10),
                surface: Color(hex: 0x1A1A1D),
                surface2: Color(hex: 0x16161A),
                text: Color(hex: 0xF2EFE8),
                text2: Color(hex: 0x98948C),
                text3: Color(hex: 0x5F5C57),
                border: Color(hex: 0x2A292C),
                border2: Color(hex: 0x3A383C),
                accent: Color(hex: 0xA6A2EE),
                accent2: Color(hex: 0xC5C2FF),
                accentSoft: Color(hex: 0x221F3D),
                success: Color(hex: 0x4DAD7C),
                successSoft: Color(hex: 0x14241D),
                warn: Color(hex: 0xD9B379),
                warnSoft: Color(hex: 0x25201A),
                danger: Color(hex: 0xD87571),
                dangerSoft: Color(hex: 0x2A1A1A),
                bubbleMeBackground: Color(hex: 0x7B73E0),
                bubbleMeForeground: Color(hex: 0xFFFFFF),
                bubbleThemBackground: Color(hex: 0x232325),
                bubbleThemForeground: Color(hex: 0xF2EFE8),
                folders: [
                    Color(hex: 0x5C3F32), Color(hex: 0x3D4A36), Color(hex: 0x4A3A22),
                    Color(hex: 0x2D3445), Color(hex: 0x4A2F3D), Color(hex: 0x3A332B)
                ]
            )
        }
    }
}

public enum ClawdiaSpacing {
    public static let xxs: CGFloat = 4
    public static let xs: CGFloat = 8
    public static let sm: CGFloat = 12
    public static let md: CGFloat = 16
    public static let lg: CGFloat = 22
    public static let xl: CGFloat = 32
}

public enum ClawdiaRadius {
    public static let sm: CGFloat = 8
    public static let md: CGFloat = 12
    public static let lg: CGFloat = 18
    public static let xl: CGFloat = 22
}

public enum ClawdiaType {
    public static func display(_ size: CGFloat = 38) -> Font {
        .system(size: size, weight: .regular, design: .serif).italic()
    }

    public static let title = Font.system(size: 28, weight: .bold, design: .default)
    public static let subhead = Font.system(size: 18, weight: .semibold, design: .default)
    public static let body = Font.system(size: 16, weight: .regular, design: .default)
    public static let caption = Font.system(size: 13, weight: .regular, design: .default)
    public static let label = Font.system(size: 12, weight: .semibold, design: .default)
    public static let mono = Font.system(size: 13, weight: .regular, design: .monospaced)
}

public extension Color {
    init(hex: UInt, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}
