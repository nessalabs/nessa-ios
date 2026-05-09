import SwiftUI
import ClawdiaDesignSystem

struct SettingsRowData: Identifiable {
    enum Accessory {
        case chevron
        case toggle
        case status(String)
    }

    let id = UUID()
    let icon: String
    let label: String
    let detail: String?
    let accessory: Accessory
    let action: (() -> Void)?

    init(
        icon: String,
        label: String,
        detail: String? = nil,
        accessory: Accessory = .chevron,
        action: (() -> Void)? = nil
    ) {
        self.icon = icon
        self.label = label
        self.detail = detail
        self.accessory = accessory
        self.action = action
    }
}

struct ClawdiaSettingsSection: View {
    @Environment(\.clawdiaTheme) private var theme
    let title: String
    let rows: [SettingsRowData]

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        VStack(alignment: .leading, spacing: ClawdiaSpacing.xs) {
            Text(title.uppercased())
                .font(ClawdiaType.label)
                .foregroundStyle(palette.text2)
                .padding(.horizontal, ClawdiaSpacing.xs)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    ClawdiaSettingsRow(row: row)
                    if index < rows.count - 1 {
                        Rectangle()
                            .fill(palette.border)
                            .frame(height: 0.5)
                            .padding(.leading, 62)
                    }
                }
            }
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: ClawdiaRadius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ClawdiaRadius.lg, style: .continuous)
                    .stroke(palette.border, lineWidth: 0.5)
            }
        }
    }
}

private struct ClawdiaSettingsRow: View {
    @Environment(\.clawdiaTheme) private var theme
    let row: SettingsRowData

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        Button {
            row.action?()
        } label: {
            HStack(spacing: ClawdiaSpacing.sm) {
                Text(row.icon)
                    .font(ClawdiaType.caption)
                    .frame(width: 32, height: 32)
                    .background(palette.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: ClawdiaRadius.sm, style: .continuous))
                Text(row.label)
                    .font(ClawdiaType.body)
                    .foregroundStyle(palette.text)
                    .lineLimit(1)
                Spacer(minLength: ClawdiaSpacing.xs)
                if let detail = row.detail {
                    Text(detail)
                        .font(ClawdiaType.caption)
                        .foregroundStyle(palette.text2)
                        .lineLimit(1)
                }
                accessoryView(palette)
            }
            .padding(.horizontal, ClawdiaSpacing.md)
            .padding(.vertical, 13)
            .background(palette.surface)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func accessoryView(_ palette: ClawdiaPalette) -> some View {
        switch row.accessory {
        case .chevron:
            Image(systemName: "chevron.right")
                .font(ClawdiaType.caption)
                .foregroundStyle(palette.text3)
        case .toggle:
            Toggle("", isOn: .constant(true))
                .labelsHidden()
                .tint(palette.accent)
        case .status(let status):
            Text(status.uppercased())
                .font(ClawdiaType.label)
                .foregroundStyle(palette.success)
        }
    }

}

struct ClawdiaProfileSettingsCard: View {
    @Environment(\.clawdiaTheme) private var theme

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        HStack(spacing: ClawdiaSpacing.sm) {
            ClawdiaAvatar(size: 56, label: "S")
            VStack(alignment: .leading, spacing: ClawdiaSpacing.xxs) {
                Text("Saurav Atwell")
                    .font(ClawdiaType.subhead)
                    .foregroundStyle(palette.text)
                Text("Personal Clawdia workspace")
                    .font(ClawdiaType.caption)
                    .foregroundStyle(palette.text2)
            }
            Spacer()
        }
        .padding(18)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: ClawdiaRadius.xl, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ClawdiaRadius.xl, style: .continuous)
                .stroke(palette.border, lineWidth: 0.5)
        }
    }
}
