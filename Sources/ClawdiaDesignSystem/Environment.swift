import SwiftUI

private struct ClawdiaThemeKey: EnvironmentKey {
    static let defaultValue: ClawdiaTheme = .light
}

public extension EnvironmentValues {
    var clawdiaTheme: ClawdiaTheme {
        get { self[ClawdiaThemeKey.self] }
        set { self[ClawdiaThemeKey.self] = newValue }
    }
}

public extension View {
    func clawdiaTheme(_ theme: ClawdiaTheme) -> some View {
        environment(\.clawdiaTheme, theme)
    }

    func clawdiaScreenBackground() -> some View {
        modifier(ClawdiaScreenBackground())
    }
}

private struct ClawdiaScreenBackground: ViewModifier {
    @Environment(\.clawdiaTheme) private var theme

    func body(content: Content) -> some View {
        let palette = ClawdiaColor.palette(theme)
        content
            .background(palette.background)
            .foregroundStyle(palette.text)
    }
}
