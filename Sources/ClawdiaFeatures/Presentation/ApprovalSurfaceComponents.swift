import SwiftUI
import ClawdiaDesignSystem

struct FloatingApprovalDemo: View {
    @Environment(\.clawdiaTheme) private var theme
    let approvals: [ApprovalRequest]
    @State private var selected: ApprovalRequest?
    @State private var showingFullDiff = false

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        ZStack(alignment: .bottom) {
            AppScroll {
                Text("approvals")
                    .font(ClawdiaType.display())
                Text("Tap any item to test the bottom-floating approval surface. These are reusable components used by app mode and development mode.")
                    .font(ClawdiaType.caption)
                    .foregroundStyle(palette.text2)
                ForEach(approvals) { approval in
                    ApprovalInlineSurface(request: approval) {
                        selected = approval
                    }
                }
                CodeReviewDiffSurface()
                FullScreenDiffLauncher {
                    showingFullDiff = true
                }
                ToolUseReceiptSurface()
            }
            if let selected {
                ApprovalBottomSheet(request: selected) {
                    self.selected = nil
                }
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: selected?.id)
        .sheet(isPresented: $showingFullDiff) {
            CodeDiffFullScreenSurface {
                showingFullDiff = false
            }
        }
    }
}

struct ApprovalInlineSurface: View {
    @Environment(\.clawdiaTheme) private var theme
    let request: ApprovalRequest
    let onOpen: () -> Void

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        Button(action: onOpen) {
            ClawdiaCard {
                VStack(alignment: .leading, spacing: ClawdiaSpacing.sm) {
                    HStack(spacing: ClawdiaSpacing.xs) {
                        ClawdiaAvatar(size: 18)
                        Text(request.title.uppercased())
                            .font(ClawdiaType.label)
                            .foregroundStyle(palette.accent)
                        Spacer()
                        Image(systemName: "arrow.up.forward")
                            .font(ClawdiaType.caption)
                            .foregroundStyle(palette.text3)
                    }
                    Text(request.detail)
                        .font(ClawdiaType.body)
                        .foregroundStyle(palette.text)
                    ApprovalKindPreview(kind: request.kind)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct ApprovalBottomSheet: View {
    @Environment(\.clawdiaTheme) private var theme
    let request: ApprovalRequest
    let onDismiss: () -> Void

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        ZStack(alignment: .bottom) {
            palette.text.opacity(0.28)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
            VStack(spacing: ClawdiaSpacing.sm) {
                Capsule()
                    .fill(palette.border2)
                    .frame(width: 36, height: 4)
                    .padding(.top, ClawdiaSpacing.sm)
                HStack {
                    Label(request.title, systemImage: iconName(for: request.kind))
                        .font(ClawdiaType.label)
                        .foregroundStyle(palette.accent)
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .frame(width: 30, height: 30)
                            .background(palette.surface2)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                ApprovalKindPreview(kind: request.kind)
                Text(request.detail)
                    .font(ClawdiaType.body)
                    .foregroundStyle(palette.text)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if request.kind == .sendEmail {
                    SwipeConfirmSurface(title: request.primaryAction)
                } else if request.kind == .deleteArchive {
                    HoldConfirmSurface(title: request.primaryAction)
                } else {
                    ClawdiaPillButton(request.primaryAction, systemImage: "checkmark") {}
                }
                ClawdiaPillButton(request.secondaryAction, kind: .soft) {}
            }
            .padding(.horizontal, ClawdiaSpacing.lg)
            .padding(.bottom, ClawdiaSpacing.lg)
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: ClawdiaRadius.xl, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ClawdiaRadius.xl, style: .continuous)
                    .stroke(palette.border, lineWidth: 0.5)
            }
            .padding(ClawdiaSpacing.sm)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func iconName(for kind: ApprovalKind) -> String {
        switch kind {
        case .draft, .documentDiff: "doc.text"
        case .transfer: "creditcard"
        case .sendEmail: "paperplane"
        case .deleteArchive: "trash"
        case .codeDiff: "curlybraces"
        case .calendarMove: "calendar"
        case .settingsChange: "gearshape"
        }
    }
}

private struct FullScreenDiffLauncher: View {
    @Environment(\.clawdiaTheme) private var theme
    let onOpen: () -> Void

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        Button(action: onOpen) {
            ClawdiaCard {
                VStack(alignment: .leading, spacing: ClawdiaSpacing.sm) {
                    Label("trip-planner.ts - full review", systemImage: "rectangle.inset.filled")
                        .font(ClawdiaType.label)
                        .foregroundStyle(palette.accent)
                    Text("Open the full-screen code diff with sticky accept-all, per-line, and request-changes actions.")
                        .font(ClawdiaType.caption)
                        .foregroundStyle(palette.text2)
                    MiniCodeDiff()
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct MiniCodeDiff: View {
    @Environment(\.clawdiaTheme) private var theme

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        VStack(alignment: .leading, spacing: 0) {
            CodeLine(number: 13, marker: "-", code: "const days = prefs.length || 5;", tint: palette.dangerSoft, markerColor: palette.danger)
            CodeLine(number: 14, marker: "+", code: "const days = clamp(prefs.length, 3, 14);", tint: palette.successSoft, markerColor: palette.success)
            CodeLine(number: 17, marker: "+", code: "return search({ days, budget, region });", tint: palette.successSoft, markerColor: palette.success)
        }
        .clipShape(RoundedRectangle(cornerRadius: ClawdiaRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ClawdiaRadius.md, style: .continuous)
                .stroke(palette.border, lineWidth: 0.5)
        }
    }
}

struct CodeDiffFullScreenSurface: View {
    @Environment(\.clawdiaTheme) private var theme
    let onClose: () -> Void

    private let lines: [CodeDiffLine] = [
        CodeDiffLine(number: 11, marker: " ", code: "import { clamp, search } from \"./utils\";"),
        CodeDiffLine(number: 12, marker: " ", code: ""),
        CodeDiffLine(number: 13, marker: " ", code: "function planTrip(prefs) {"),
        CodeDiffLine(number: 14, marker: "-", code: "  const days = prefs.length || 5;"),
        CodeDiffLine(number: 14, marker: "+", code: "  const days = clamp(prefs.length, 3, 14);"),
        CodeDiffLine(number: 15, marker: " ", code: "  const budget = prefs.budget;"),
        CodeDiffLine(number: 16, marker: " ", code: "  const region = prefs.region ?? \"EU\";"),
        CodeDiffLine(number: 17, marker: "-", code: "  return search(days, budget);"),
        CodeDiffLine(number: 17, marker: "+", code: "  if (budget < 500) return null;"),
        CodeDiffLine(number: 18, marker: "+", code: "  return search({ days, budget, region });"),
        CodeDiffLine(number: 19, marker: " ", code: "}"),
        CodeDiffLine(number: 20, marker: " ", code: ""),
        CodeDiffLine(number: 21, marker: " ", code: "export default planTrip;")
    ]

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        VStack(spacing: 0) {
            HStack(spacing: ClawdiaSpacing.sm) {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .font(ClawdiaType.subhead)
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.accent)
                VStack(alignment: .leading, spacing: ClawdiaSpacing.xxs) {
                    Text("trip-planner.ts")
                        .font(ClawdiaType.body.weight(.semibold))
                    HStack(spacing: ClawdiaSpacing.xs) {
                        Text("+3")
                            .foregroundStyle(palette.success)
                        Text("-2")
                            .foregroundStyle(palette.danger)
                        Text("2 hunks")
                    }
                    .font(ClawdiaType.caption)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .frame(width: 32, height: 32)
                        .background(palette.surface2)
                        .clipShape(RoundedRectangle(cornerRadius: ClawdiaRadius.md, style: .continuous))
                }
                .buttonStyle(.plain)
                .foregroundStyle(palette.text2)
            }
            .padding(.horizontal, ClawdiaSpacing.md)
            .padding(.top, ClawdiaSpacing.lg)
            .padding(.bottom, ClawdiaSpacing.sm)
            .background(palette.background)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(palette.border)
                    .frame(height: 0.5)
            }

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(lines) { line in
                        CodeLine(
                            number: line.number,
                            marker: line.marker,
                            code: line.code,
                            tint: tint(for: line, palette: palette),
                            markerColor: markerColor(for: line, palette: palette)
                        )
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: ClawdiaRadius.lg, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: ClawdiaRadius.lg, style: .continuous)
                        .stroke(palette.border, lineWidth: 0.5)
                }
                .padding(ClawdiaSpacing.md)
            }

            VStack(spacing: ClawdiaSpacing.xs) {
                ClawdiaPillButton("Accept all changes", systemImage: "checkmark") {}
                HStack(spacing: ClawdiaSpacing.xs) {
                    ClawdiaPillButton("Per-line", kind: .soft) {}
                    ClawdiaPillButton("Request changes", kind: .soft) {}
                }
            }
            .padding(.horizontal, ClawdiaSpacing.md)
            .padding(.top, ClawdiaSpacing.sm)
            .padding(.bottom, ClawdiaSpacing.lg)
            .background(.ultraThinMaterial)
        }
        .clawdiaScreenBackground()
    }

    private func tint(for line: CodeDiffLine, palette: ClawdiaPalette) -> Color {
        if line.marker == "+" {
            return palette.successSoft
        }
        if line.marker == "-" {
            return palette.dangerSoft
        }
        return palette.surface2
    }

    private func markerColor(for line: CodeDiffLine, palette: ClawdiaPalette) -> Color {
        if line.marker == "+" {
            return palette.success
        }
        if line.marker == "-" {
            return palette.danger
        }
        return palette.text3
    }
}

private struct CodeDiffLine: Identifiable {
    let id = UUID()
    let number: Int
    let marker: String
    let code: String
}

private struct CodeLine: View {
    @Environment(\.clawdiaTheme) private var theme
    let number: Int
    let marker: String
    let code: String
    let tint: Color
    let markerColor: Color

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        HStack(spacing: 0) {
            Text("\(number)")
                .font(ClawdiaType.mono)
                .foregroundStyle(palette.text3)
                .frame(width: 34, alignment: .trailing)
                .padding(.trailing, ClawdiaSpacing.xs)
            Text(marker)
                .font(ClawdiaType.mono)
                .foregroundStyle(markerColor)
                .frame(width: 20)
            Text(code)
                .font(ClawdiaType.mono)
                .foregroundStyle(palette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, ClawdiaSpacing.xs)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, ClawdiaSpacing.xs)
        .background(tint)
    }
}

private struct ApprovalKindPreview: View {
    @Environment(\.clawdiaTheme) private var theme
    let kind: ApprovalKind

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        Group {
            switch kind {
            case .draft:
                Text("Mia, thirty-three looks good on you. Almost as good as that very wrong opinion you keep having about tea.")
                    .font(ClawdiaType.caption)
            case .transfer:
                HStack {
                    StatPair(label: "Checking", before: "$8,420", after: "$7,220")
                    StatPair(label: "Travel", before: "$640", after: "$1,840")
                }
            case .sendEmail:
                Text("Reply to Marcus with the revised PR approach. No other recipients.")
                    .font(ClawdiaType.caption)
            case .deleteArchive:
                Label("Permanent action - 14 chats", systemImage: "exclamationmark.triangle")
                    .font(ClawdiaType.caption)
                    .foregroundStyle(palette.danger)
            case .codeDiff:
                CodeSnippetPreview()
            case .documentDiff:
                Text("Track-changes rewrite with reasoning attached.")
                    .font(ClawdiaType.caption)
            case .calendarMove:
                Text("Wed 2 PM -> Thu 11 AM. No conflicts.")
                    .font(ClawdiaType.caption)
            case .settingsChange:
                Text("Quiet hours, approvals-only interruptions, and Slack alert scope.")
                    .font(ClawdiaType.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ClawdiaSpacing.sm)
        .background(palette.surface2)
        .clipShape(RoundedRectangle(cornerRadius: ClawdiaRadius.md, style: .continuous))
        .foregroundStyle(palette.text)
    }
}

private struct StatPair: View {
    let label: String
    let before: String
    let after: String

    var body: some View {
        VStack(alignment: .leading, spacing: ClawdiaSpacing.xxs) {
            Text(label.uppercased()).font(ClawdiaType.label)
            HStack(spacing: ClawdiaSpacing.xs) {
                Text(before).strikethrough()
                Text(after)
            }
            .font(ClawdiaType.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CodeSnippetPreview: View {
    @Environment(\.clawdiaTheme) private var theme

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        VStack(alignment: .leading, spacing: ClawdiaSpacing.xxs) {
            Text("- const days = prefs.length || 5;")
                .foregroundStyle(palette.danger)
            Text("+ const days = clamp(prefs.length, 3, 14);")
                .foregroundStyle(palette.success)
        }
        .font(ClawdiaType.mono)
    }
}

private struct SwipeConfirmSurface: View {
    @Environment(\.clawdiaTheme) private var theme
    let title: String
    @State private var confirmed = false
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        GeometryReader { proxy in
            let knob: CGFloat = 44
            let inset: CGFloat = 6
            let travel = max(proxy.size.width - knob - inset * 2, 1)
            let offset = confirmed ? travel : min(max(dragOffset, 0), travel)
            let progress = offset / travel
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(palette.surface2)
                    .overlay {
                        Capsule().stroke(palette.border, lineWidth: 0.5)
                    }
                Capsule()
                    .fill(palette.accent.opacity(0.20))
                    .frame(width: offset + knob + inset)
                    .opacity(confirmed ? 0.65 : 0.42)
                Text(confirmed ? "Sent in dev mode" : "\(title) ->")
                    .font(ClawdiaType.caption.weight(.semibold))
                    .foregroundStyle(palette.text2.opacity(1 - Double(progress) * 0.45))
                    .frame(maxWidth: .infinity)
                Circle()
                    .fill(confirmed ? palette.success : palette.accent)
                    .frame(width: knob, height: knob)
                    .shadow(color: palette.accent.opacity(0.34), radius: 12, y: 4)
                    .overlay {
                        Image(systemName: confirmed ? "checkmark" : "paperplane.fill")
                            .foregroundStyle(palette.bubbleMeForeground)
                    }
                    .offset(x: inset + offset)
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { value in
                                guard !confirmed else {
                                    return
                                }
                                dragOffset = min(max(value.translation.width, 0), travel)
                            }
                            .onEnded { value in
                                let proposed = min(max(value.translation.width, 0), travel)
                                if proposed > travel * 0.82 {
                                    confirmed = true
                                    dragOffset = travel
                                } else {
                                    dragOffset = 0
                                }
                            }
                    )
            }
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: dragOffset)
            .animation(.spring(response: 0.28, dampingFraction: 0.82), value: confirmed)
        }
        .frame(height: 56)
    }
}

private struct HoldConfirmSurface: View {
    @Environment(\.clawdiaTheme) private var theme
    let title: String
    @State private var armed = false

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        Button {
            armed.toggle()
        } label: {
            VStack(spacing: ClawdiaSpacing.xs) {
                ZStack {
                    Circle()
                        .fill(palette.dangerSoft)
                        .frame(width: 78, height: 78)
                    Circle()
                        .trim(from: 0, to: armed ? 0.85 : 0.32)
                        .stroke(palette.danger, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 78, height: 78)
                        .rotationEffect(.degrees(-90))
                    Image(systemName: armed ? "checkmark" : "trash")
                        .foregroundStyle(.white)
                        .frame(width: 52, height: 52)
                        .background(palette.danger)
                        .clipShape(Circle())
                }
                Text(armed ? "Confirmed in dev mode" : title)
                    .font(ClawdiaType.caption.weight(.semibold))
                    .foregroundStyle(palette.text2)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

struct CodeReviewDiffSurface: View {
    @Environment(\.clawdiaTheme) private var theme
    @State private var tab = "v2"

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        ClawdiaCard {
            VStack(alignment: .leading, spacing: ClawdiaSpacing.sm) {
                Label("Reply to Marcus - code review", systemImage: "curlybraces")
                    .font(ClawdiaType.label)
                    .foregroundStyle(palette.accent)
                Picker("Version", selection: $tab) {
                    Text("v1 original").tag("v1")
                    Text("v2 suggested").tag("v2")
                }
                .pickerStyle(.segmented)
                Text(tab == "v1" ? "Wanted to circle back on the PR. I think there are some issues with the approach." : "Two things on the PR: the cache key collides on stale tabs, and the 401 path silently logs out. I'll patch both Tuesday.")
                    .font(ClawdiaType.caption)
                    .padding(ClawdiaSpacing.sm)
                    .background(tab == "v2" ? palette.accentSoft : palette.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: ClawdiaRadius.md, style: .continuous))
                HStack {
                    ClawdiaPillButton("Use \(tab)", systemImage: "checkmark") {}
                    ClawdiaPillButton("Try another", kind: .soft) {}
                }
            }
        }
    }
}

struct ToolUseReceiptSurface: View {
    var body: some View {
        RichDataCard(title: "Agent activity", systemImage: "list.bullet.rectangle") {
            ForEach(["Searching notes", "Reading 3 chats", "Drafting card", "Checking tone", "Saving draft"], id: \.self) { step in
                Label(step, systemImage: "checkmark.circle.fill")
                    .font(ClawdiaType.caption)
            }
        }
    }
}
