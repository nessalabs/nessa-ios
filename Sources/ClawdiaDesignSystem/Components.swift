import SwiftUI

public struct ClawdiaMark: View {
    private let size: CGFloat

    public init(size: CGFloat = 40) {
        self.size = size
    }

    public var body: some View {
        Canvas { context, _ in
            context.fill(
                Path(ellipseIn: CGRect(x: size * 0.275, y: size * 0.495, width: size * 0.45, height: size * 0.36)),
                with: .color(.white)
            )
            context.fill(
                Path(ellipseIn: CGRect(x: size * 0.175, y: size * 0.27, width: size * 0.17, height: size * 0.23)),
                with: .color(.white)
            )
            context.fill(
                Path(ellipseIn: CGRect(x: size * 0.415, y: size * 0.13, width: size * 0.17, height: size * 0.24)),
                with: .color(.white)
            )
            context.fill(
                Path(ellipseIn: CGRect(x: size * 0.655, y: size * 0.27, width: size * 0.17, height: size * 0.23)),
                with: .color(Color(hex: 0x7B73E0))
            )
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

public struct ClawdiaAvatar: View {
    private let size: CGFloat
    private let label: String?

    public init(size: CGFloat = 40, label: String? = nil) {
        self.size = size
        self.label = label
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0xB5B0F0), Color(hex: 0x7B73E0), Color(hex: 0x4D44B8)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            if let label {
                Text(label)
                    .font(.system(size: size * 0.4, weight: .semibold))
                    .foregroundStyle(.white)
            } else {
                ClawdiaMark(size: size * 0.62)
            }
        }
        .frame(width: size, height: size)
    }
}

public struct ClawdiaWordmark: View {
    public init() {}

    public var body: some View {
        HStack(alignment: .center, spacing: ClawdiaSpacing.xs) {
            ClawdiaAvatar(size: 34)
            Text("clawdia")
                .font(ClawdiaType.display(34))
        }
        .accessibilityElement(children: .combine)
    }
}

public struct ClawdiaPrimaryButton: View {
    @Environment(\.clawdiaTheme) private var theme
    private let title: String
    private let systemImage: String?
    private let action: () -> Void

    public init(_ title: String, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        let palette = ClawdiaColor.palette(theme)
        Button(action: action) {
            Label(title, systemImage: systemImage ?? "checkmark")
                .labelStyle(.titleAndIcon)
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(palette.text)
                .foregroundStyle(palette.background)
                .clipShape(RoundedRectangle(cornerRadius: ClawdiaRadius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

public struct ClawdiaPillButton: View {
    public enum Kind {
        case primary
        case soft
        case accent
        case danger
    }

    @Environment(\.clawdiaTheme) private var theme
    private let title: String
    private let kind: Kind
    private let systemImage: String?
    private let action: () -> Void

    public init(_ title: String, kind: Kind = .primary, systemImage: String? = nil, action: @escaping () -> Void = {}) {
        self.title = title
        self.kind = kind
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        let palette = ClawdiaColor.palette(theme)
        Button(action: action) {
            HStack(spacing: ClawdiaSpacing.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(.system(size: 14, weight: .semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(background(palette))
            .foregroundStyle(foreground(palette))
            .clipShape(RoundedRectangle(cornerRadius: ClawdiaRadius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ClawdiaRadius.md, style: .continuous)
                    .stroke(kind == .soft ? palette.border : .clear, lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
    }

    private func background(_ palette: ClawdiaPalette) -> Color {
        switch kind {
        case .primary: palette.text
        case .soft: palette.surface2
        case .accent: palette.accent
        case .danger: palette.dangerSoft
        }
    }

    private func foreground(_ palette: ClawdiaPalette) -> Color {
        switch kind {
        case .primary: palette.background
        case .soft: palette.text
        case .accent: .white
        case .danger: palette.danger
        }
    }
}

public struct ClawdiaCard<Content: View>: View {
    @Environment(\.clawdiaTheme) private var theme
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        let palette = ClawdiaColor.palette(theme)
        content
            .padding(ClawdiaSpacing.md)
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: ClawdiaRadius.xl, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ClawdiaRadius.xl, style: .continuous)
                    .stroke(palette.border, lineWidth: 0.5)
            }
    }
}

public struct ClawdiaSection<Content: View>: View {
    @Environment(\.clawdiaTheme) private var theme
    private let title: String
    private let content: Content

    public init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    public var body: some View {
        let palette = ClawdiaColor.palette(theme)
        VStack(alignment: .leading, spacing: ClawdiaSpacing.xs) {
            Text(title.uppercased())
                .font(ClawdiaType.label)
                .foregroundStyle(palette.text2)
            content
        }
    }
}
