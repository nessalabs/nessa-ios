import SwiftUI
import ClawdiaDesignSystem

public struct DevModeRootView: View {
    @StateObject private var store: DevModeStore
    @State private var theme: ClawdiaTheme = .light
    @AppStorage("didCompleteOnboarding") private var didCompleteOnboarding = false
    @State private var selectedTab: AppTab = .chats
    @State private var showingChat = false
    @State private var developmentScreen: DevScreen?

    public init(store: DevModeStore = DevModeStore()) {
        _store = StateObject(wrappedValue: store)
    }

    public var body: some View {
        NavigationStack {
            Group {
                if didCompleteOnboarding {
                    AppShell(
                        state: store.state,
                        selectedTab: $selectedTab,
                        showingChat: $showingChat,
                        theme: $theme,
                        developmentScreen: $developmentScreen
                    )
                } else {
                    OnboardingFlowView {
                        didCompleteOnboarding = true
                        selectedTab = .chats
                    }
                }
            }
            .navigationDestination(isPresented: $showingChat) {
                ChatScreen(state: store.state)
            }
        }
        .clawdiaTheme(theme)
        .preferredColorScheme(theme == .dark ? .dark : .light)
        .onChange(of: developmentScreen) { _, newValue in
            if let newValue {
                store.recordScreen(newValue)
            }
        }
    }
}

private enum AppTab: String, CaseIterable, Identifiable {
    case chats
    case calendar
    case voice
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chats: "Chats"
        case .calendar: "Calendar"
        case .voice: "Voice"
        case .settings: "You"
        }
    }

    var systemImage: String {
        switch self {
        case .chats: "bubble.left.and.bubble.right"
        case .calendar: "calendar"
        case .voice: "mic"
        case .settings: "person"
        }
    }
}

private struct AppShell: View {
    let state: MockAppState
    @Binding var selectedTab: AppTab
    @Binding var showingChat: Bool
    @Binding var theme: ClawdiaTheme
    @Binding var developmentScreen: DevScreen?
    @State private var showingAreasManager = false
    @State private var showingSearch = false

    var body: some View {
        ZStack {
            if let developmentScreen {
                DevelopmentScreen(
                    selectedScreen: Binding(
                        get: { developmentScreen },
                        set: { self.developmentScreen = $0 }
                    ),
                    theme: $theme,
                    state: state,
                    onClose: { self.developmentScreen = nil }
                )
            } else if showingAreasManager {
                FolderManagerScreen(folders: state.folders) {
                    showingAreasManager = false
                }
            } else if showingSearch {
                SearchScreen(state: state) {
                    showingSearch = false
                }
            } else {
                TabView(selection: $selectedTab) {
                    HomeScreen(state: state, onSearch: {
                        showingSearch = true
                    }) {
                        showingChat = true
                    }
                    .tag(AppTab.chats)
                    .tabItem {
                        Label(AppTab.chats.title, systemImage: AppTab.chats.systemImage)
                    }

                    CalendarScreen()
                        .tag(AppTab.calendar)
                        .tabItem {
                            Label(AppTab.calendar.title, systemImage: AppTab.calendar.systemImage)
                        }

                    VoiceScreen()
                        .tag(AppTab.voice)
                        .tabItem {
                            Label(AppTab.voice.title, systemImage: AppTab.voice.systemImage)
                        }

                    SettingsScreen(theme: $theme, onOpenAreas: {
                        showingAreasManager = true
                    }) { screen in
                        developmentScreen = screen
                    }
                    .tag(AppTab.settings)
                    .tabItem {
                        Label(AppTab.settings.title, systemImage: AppTab.settings.systemImage)
                    }
                }
                .tint(ClawdiaColor.palette(theme).accent)
            }
        }
    }
}

private struct DevelopmentScreen: View {
    @Binding var selectedScreen: DevScreen
    @Binding var theme: ClawdiaTheme
    let state: MockAppState
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            DevelopmentHeader(
                selectedScreen: $selectedScreen,
                theme: $theme,
                onClose: onClose
            )
            Divider()
            ScreenHost(screen: selectedScreen, state: state)
        }
    }
}

private struct DevelopmentHeader: View {
    @Environment(\.clawdiaTheme) private var currentTheme
    @Binding var selectedScreen: DevScreen
    @Binding var theme: ClawdiaTheme
    let onClose: () -> Void

    var body: some View {
        let palette = ClawdiaColor.palette(currentTheme)
        HStack(spacing: ClawdiaSpacing.sm) {
            Button(action: onClose) {
                Image(systemName: "chevron.left")
                    .font(ClawdiaType.subhead)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.accent)

            Picker("Screen", selection: $selectedScreen) {
                ForEach(DevScreen.allCases) { screen in
                    Text(screen.title).tag(screen)
                }
            }
            .pickerStyle(.menu)
            .tint(palette.accent)

            Spacer()

            Picker("Theme", selection: $theme) {
                ForEach(ClawdiaTheme.allCases, id: \.self) { theme in
                    Text(theme.rawValue.capitalized).tag(theme)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 150)
        }
        .padding(.horizontal, ClawdiaSpacing.md)
        .padding(.vertical, ClawdiaSpacing.xs)
        .background(palette.background)
    }
}

private struct ScreenHost: View {
    let screen: DevScreen
    let state: MockAppState

    var body: some View {
        Group {
            switch screen {
            case .onboarding:
                OnboardingFlowView()
            case .home:
                HomeScreen(state: state)
            case .chat:
                ChatScreen(state: state, showsNavigationHeader: false)
            case .voice:
                VoiceScreen()
            case .approvals:
                ApprovalsGallery(approvals: state.approvals)
            case .search:
                SearchScreen()
            case .calendar:
                CalendarScreen()
            case .folders:
                FolderManagerScreen(folders: state.folders)
            case .settings:
                SettingsScreen()
            case .connectedApps:
                ConnectedAppsScreen()
            case .memory:
                MemoryGraphScreen()
            case .contextNotes:
                ContextNotesScreen()
            case .contextBoard:
                ContextBoardScreen()
            case .designSystem:
                DesignSystemGallery()
            }
        }
    }
}

public struct OnboardingFlowView: View {
    @Environment(\.clawdiaTheme) private var theme
    @State private var step = 0
    private let onComplete: () -> Void

    public init(onComplete: @escaping () -> Void = {}) {
        self.onComplete = onComplete
    }

    public var body: some View {
        let palette = ClawdiaColor.palette(theme)
        VStack(alignment: .leading, spacing: ClawdiaSpacing.xl) {
            Spacer(minLength: 32)
            if step == 0 {
                Text("hi, I'm\nClawdia.")
                    .font(ClawdiaType.display(56))
                Text("I'll help you stay on top of life. We can chat, plan, draft, decide, and review approvals in one place.")
                    .font(ClawdiaType.subhead)
                    .foregroundStyle(palette.text2)
            } else if step == 1 {
                Text("what's on your plate?")
                    .font(ClawdiaType.display())
                Text("Pick a few areas to start. We'll make a folder for each one.")
                    .font(ClawdiaType.body)
                    .foregroundStyle(palette.text2)
                AreaPickerRows()
            } else {
                Text("connect to Clawdia")
                    .font(ClawdiaType.display())
                Text("Local mode talks to the Clawdia process on your machine. Cloud is reserved for the future hosted plan.")
                    .font(ClawdiaType.body)
                    .foregroundStyle(palette.text2)
                ConnectionCard()
            }
            Spacer()
            PageDots(active: step, count: 3)
            ClawdiaPrimaryButton(step == 2 ? "Start using Clawdia" : "Continue", systemImage: "arrow.right") {
                if step == 2 {
                    onComplete()
                } else {
                    step += 1
                }
            }
        }
        .padding(ClawdiaSpacing.xl)
        .clawdiaScreenBackground()
    }
}

private struct AreaPickerRows: View {
    @Environment(\.clawdiaTheme) private var theme

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        VStack(spacing: ClawdiaSpacing.xs) {
            ForEach(Array(LifeArea.allCases.enumerated()), id: \.element) { index, area in
                HStack(spacing: ClawdiaSpacing.sm) {
                    Image(systemName: area.icon)
                        .frame(width: 36, height: 36)
                        .background(palette.folders[index])
                        .clipShape(RoundedRectangle(cornerRadius: ClawdiaRadius.md, style: .continuous))
                    Text(area.title)
                        .font(ClawdiaType.body)
                    Spacer()
                    Image(systemName: index < 4 ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(index < 4 ? palette.accent : palette.border2)
                }
                .padding(ClawdiaSpacing.sm)
                .background(palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: ClawdiaRadius.lg, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: ClawdiaRadius.lg, style: .continuous)
                        .stroke(index < 4 ? palette.accent : palette.border, lineWidth: index < 4 ? 1.5 : 0.5)
                }
            }
        }
    }
}

private struct ConnectionCard: View {
    @Environment(\.clawdiaTheme) private var theme

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        ClawdiaCard {
            VStack(alignment: .leading, spacing: ClawdiaSpacing.sm) {
                Label("Localhost:8787", systemImage: "desktopcomputer")
                    .font(ClawdiaType.subhead)
                Text("Ready for local app communication. Cloud endpoint can use the same port interface later.")
                    .font(ClawdiaType.caption)
                    .foregroundStyle(palette.text2)
                HStack {
                    StatusPill("Connected", systemImage: "checkmark.circle")
                    StatusPill("Logs on", systemImage: "waveform")
                }
            }
        }
    }
}

private struct PageDots: View {
    @Environment(\.clawdiaTheme) private var theme
    let active: Int
    let count: Int

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        HStack(spacing: ClawdiaSpacing.xs) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == active ? palette.accent : palette.border2)
                    .frame(width: index == active ? 22 : 7, height: 7)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

public struct HomeScreen: View {
    @Environment(\.clawdiaTheme) private var theme
    let state: MockAppState
    let onSearch: () -> Void
    let onOpenChat: () -> Void
    @State private var customAreas: [CustomArea] = []
    @State private var showingNewArea = false
    @State private var draftAreaName = ""
    @State private var isSearchPinned = false
    @State private var homeTopBaseline: CGFloat?

    public init(
        state: MockAppState = .preview,
        onSearch: @escaping () -> Void = {},
        onOpenChat: @escaping () -> Void = {}
    ) {
        self.state = state
        self.onSearch = onSearch
        self.onOpenChat = onOpenChat
    }

    public var body: some View {
        let palette = ClawdiaColor.palette(theme)
        ZStack(alignment: .top) {
            homeScrollView

            if isSearchPinned {
                PinnedHomeSearchHeader(onSearch: onSearch)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .background(palette.background)
        .sheet(isPresented: $showingNewArea) {
            NewAreaSheet(name: $draftAreaName) {
                let name = draftAreaName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    customAreas.append(CustomArea(name: name))
                }
                draftAreaName = ""
                showingNewArea = false
            } onCancel: {
                draftAreaName = ""
                showingNewArea = false
            }
        }
    }

    @ViewBuilder
    private var homeScrollView: some View {
        if #available(iOS 18.0, macOS 15.0, *) {
            baseHomeScrollView
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    geometry.contentOffset.y
                } action: { _, offset in
                    setSearchPinned(offset > 28)
                }
        } else {
            baseHomeScrollView
                .onPreferenceChange(HomeScrollOffsetKey.self) { offset in
                    if homeTopBaseline == nil {
                        homeTopBaseline = offset
                    }
                    setSearchPinned((homeTopBaseline ?? offset) - offset > 28)
                }
        }
    }

    private var baseHomeScrollView: some View {
        GeometryReader { proxy in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: ClawdiaSpacing.lg) {
                    GeometryReader { proxy in
                        Color.clear
                            .preference(key: HomeScrollOffsetKey.self, value: proxy.frame(in: .global).minY)
                    }
                    .frame(height: 1)

                    GreetingHeader()
                        .padding(.top, ClawdiaSpacing.lg)

                    SearchBar(text: "Search chats and folders", action: onSearch)
                        .opacity(isSearchPinned ? 0 : 1)
                        .allowsHitTesting(!isSearchPinned)
                        .accessibilityHidden(isSearchPinned)

                    FolderGrid(folders: state.folders, customAreas: customAreas) {
                        showingNewArea = true
                    }
                    ChatList(chats: state.chats, onOpenChat: onOpenChat)
                }
                .padding(.horizontal, ClawdiaSpacing.lg)
                .padding(.bottom, 112)
                .frame(maxWidth: 520, alignment: .topLeading)
                .frame(width: proxy.size.width)
            }
        }
    }

    private func setSearchPinned(_ shouldPin: Bool) {
        guard shouldPin != isSearchPinned else {
            return
        }
        withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
            isSearchPinned = shouldPin
        }
    }
}

private struct HomeScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct PinnedHomeSearchHeader: View {
    @Environment(\.clawdiaTheme) private var theme
    let onSearch: () -> Void

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        SearchBar(text: "Search chats and folders", action: onSearch)
            .padding(.horizontal, ClawdiaSpacing.lg)
            .padding(.top, ClawdiaSpacing.xs)
            .padding(.bottom, ClawdiaSpacing.lg)
            .frame(maxWidth: 520, alignment: .leading)
            .frame(maxWidth: .infinity)
            .background(alignment: .top) {
                Rectangle()
                    .fill(palette.background)
                    .frame(height: 260)
                    .offset(y: -160)
                    .ignoresSafeArea(edges: .top)
            }
    }
}

private struct CustomArea: Identifiable {
    let id = UUID()
    let name: String
}

private struct GreetingHeader: View {
    @Environment(\.clawdiaTheme) private var theme

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        VStack(alignment: .leading, spacing: ClawdiaSpacing.xs) {
            Text("Friday morning")
                .font(ClawdiaType.caption)
                .foregroundStyle(palette.text2)
            Text("hey, Saurav")
                .font(ClawdiaType.display())
            Text("what are we tackling today?")
                .font(ClawdiaType.subhead)
                .foregroundStyle(palette.text2)
        }
    }
}

private struct SearchBar: View {
    @Environment(\.clawdiaTheme) private var theme
    let text: String
    var action: (() -> Void)?

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        let content = HStack(spacing: ClawdiaSpacing.xs) {
            Image(systemName: "magnifyingglass")
            Text(text)
                .font(ClawdiaType.caption)
            Spacer()
        }
        .foregroundStyle(palette.text3)
        .padding(ClawdiaSpacing.sm)
        .background(palette.surface2)
        .clipShape(RoundedRectangle(cornerRadius: ClawdiaRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ClawdiaRadius.md, style: .continuous)
                .stroke(palette.border, lineWidth: 0.5)
        }
        if let action {
            Button(action: action) {
                content
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }
}

private struct FolderGrid: View {
    let folders: [FolderSummary]
    let customAreas: [CustomArea]
    let onCreateArea: () -> Void

    var body: some View {
        ClawdiaSection("Areas of life") {
            VStack(spacing: ClawdiaSpacing.xs) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: ClawdiaSpacing.xs) {
                    ForEach(Array(folders.prefix(4).enumerated()), id: \.element.id) { index, folder in
                        FolderTile(folder: folder, colorIndex: index)
                    }
                    ForEach(Array(customAreas.enumerated()), id: \.element.id) { index, area in
                        CustomAreaTile(area: area, colorIndex: index + 4)
                    }
                }
                NewAreaTile(title: "New area", subtitle: "Group chats by what matters", onTap: onCreateArea)
            }
        }
    }
}

private struct FolderTile: View {
    @Environment(\.clawdiaTheme) private var theme
    let folder: FolderSummary
    let colorIndex: Int

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        Button {
        } label: {
            ClawdiaCard {
            VStack(alignment: .leading, spacing: ClawdiaSpacing.sm) {
                Image(systemName: folder.id.icon)
                    .frame(width: 44, height: 44)
                    .background(palette.folders[colorIndex % palette.folders.count])
                    .clipShape(RoundedRectangle(cornerRadius: ClawdiaRadius.md, style: .continuous))
                Text(folder.id.title)
                    .font(ClawdiaType.body.weight(.semibold))
                Text("\(folder.chatCount) chats - \(folder.lastActivity)")
                    .font(ClawdiaType.caption)
                    .foregroundStyle(palette.text2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        }
        .buttonStyle(.plain)
    }
}

private struct NewAreaTile: View {
    @Environment(\.clawdiaTheme) private var theme
    let title: String
    let subtitle: String
    let onTap: () -> Void

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        Button(action: onTap) {
            HStack(spacing: ClawdiaSpacing.sm) {
                Image(systemName: "plus")
                    .font(ClawdiaType.subhead)
                    .frame(width: 44, height: 44)
                    .background(palette.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: ClawdiaRadius.md, style: .continuous))
                VStack(alignment: .leading, spacing: ClawdiaSpacing.xxs) {
                    Text(title)
                        .font(ClawdiaType.body.weight(.semibold))
                    Text(subtitle)
                        .font(ClawdiaType.caption)
                        .foregroundStyle(palette.text2)
                }
                Spacer()
            }
            .padding(ClawdiaSpacing.md)
            .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
            .background(palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: ClawdiaRadius.xl, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: ClawdiaRadius.xl, style: .continuous)
                    .stroke(palette.border2, style: StrokeStyle(lineWidth: 0.8, dash: [4]))
            }
        }
        .buttonStyle(.plain)
    }
}

private struct CustomAreaTile: View {
    @Environment(\.clawdiaTheme) private var theme
    let area: CustomArea
    let colorIndex: Int

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        Button {
        } label: {
            ClawdiaCard {
                VStack(alignment: .leading, spacing: ClawdiaSpacing.sm) {
                    Image(systemName: "sparkles")
                        .frame(width: 44, height: 44)
                        .background(palette.folders[colorIndex % palette.folders.count])
                        .clipShape(RoundedRectangle(cornerRadius: ClawdiaRadius.md, style: .continuous))
                    Text(area.name)
                        .font(ClawdiaType.body.weight(.semibold))
                    Text("0 chats - new")
                        .font(ClawdiaType.caption)
                        .foregroundStyle(palette.text2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct NewAreaSheet: View {
    @Environment(\.clawdiaTheme) private var theme
    @Binding var name: String
    let onCreate: () -> Void
    let onCancel: () -> Void
    @FocusState private var isNameFocused: Bool

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        NavigationStack {
            ZStack {
                palette.background
                    .ignoresSafeArea()
                    .onTapGesture {
                        isNameFocused = false
                    }

                VStack(alignment: .leading, spacing: ClawdiaSpacing.lg) {
                    Text("Create new area")
                        .font(ClawdiaType.display(34))
                    Text("Group related chats, tasks, approvals, and context under one area of life.")
                        .font(ClawdiaType.body)
                        .foregroundStyle(palette.text2)
                    TextField("Area name", text: $name)
                        .focused($isNameFocused)
                        .font(ClawdiaType.body)
                        .padding(ClawdiaSpacing.md)
                        .background(palette.surface2)
                        .clipShape(RoundedRectangle(cornerRadius: ClawdiaRadius.lg, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: ClawdiaRadius.lg, style: .continuous)
                                .stroke(palette.border, lineWidth: 0.5)
                        }
                    Spacer()
                        .contentShape(Rectangle())
                        .onTapGesture {
                            isNameFocused = false
                        }
                    ClawdiaPrimaryButton("Create area", systemImage: "plus") {
                        onCreate()
                    }
                }
                .padding(ClawdiaSpacing.lg)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
    }
}

private struct ChatList: View {
    let chats: [ChatPreview]
    let onOpenChat: () -> Void

    var body: some View {
        ClawdiaSection("Recent") {
            VStack(spacing: 0) {
                ForEach(chats) { chat in
                    ChatRow(chat: chat, onOpenChat: onOpenChat)
                    if chat.id != chats.last?.id {
                        Divider()
                    }
                }
            }
        }
    }
}

private struct ChatRow: View {
    @Environment(\.clawdiaTheme) private var theme
    let chat: ChatPreview
    let onOpenChat: () -> Void

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        Button(action: onOpenChat) {
            HStack(alignment: .top, spacing: ClawdiaSpacing.sm) {
                ClawdiaAvatar(size: 42, label: chat.title.hasPrefix("Clawdia") ? nil : String(chat.title.prefix(1)))
                VStack(alignment: .leading, spacing: ClawdiaSpacing.xxs) {
                    HStack {
                        Text(chat.title)
                            .font(ClawdiaType.body.weight(.semibold))
                        if chat.pinned {
                            Image(systemName: "pin.fill")
                                .font(ClawdiaType.caption)
                                .foregroundStyle(palette.text3)
                        }
                        Spacer()
                        Text(chat.time)
                            .font(ClawdiaType.caption)
                            .foregroundStyle(palette.text3)
                    }
                    Text(chat.preview)
                        .font(ClawdiaType.caption)
                        .foregroundStyle(chat.unread ? palette.text : palette.text2)
                        .lineLimit(2)
                }
            }
            .padding(ClawdiaSpacing.sm)
            .background(palette.surface)
        }
        .buttonStyle(.plain)
    }
}

public struct ChatScreen: View {
    let state: MockAppState
    private let showsNavigationHeader: Bool
    @State private var sentMessages: [String] = []
    @State private var floatingApproval: ApprovalRequest?
    @State private var showingAgentDetails = false
    @FocusState private var isComposerFocused: Bool

    public init(
        state: MockAppState = .preview,
        onBack: @escaping () -> Void = {},
        showsNavigationHeader: Bool = true
    ) {
        self.state = state
        self.showsNavigationHeader = showsNavigationHeader
    }

    public var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                AppScroll(keyboardDismissMode: .interactively, bottomPadding: ClawdiaSpacing.lg) {
                    MessageBubble("Morning. I noticed your sister's birthday is in 4 days. Want me to start a reminder thread?", fromMe: false)
                    MessageBubble("yes pls. and help me draft her a card", fromMe: true)
                    ToolUseInline()
                    MessageBubble("Here's a draft leaning warm with a tiny joke.", fromMe: false)
                    if let approval = state.approvals.first {
                        ApprovalInlineSurface(request: approval) {
                            floatingApproval = approval
                        }
                    }
                    MessageBubble("love it. what's my week look like and where's spending?", fromMe: true)
                    TodoCard()
                    FinanceCard()
                    StockCard()
                    ForEach(sentMessages, id: \.self) { message in
                        MessageBubble(message, fromMe: true)
                        MessageBubble("Got it. I logged that in dev mode so we can wire the local Clawdia response next.", fromMe: false)
                    }
                }
                .onTapGesture {
                    isComposerFocused = false
                }
            }
            if let floatingApproval {
                ApprovalBottomSheet(request: floatingApproval) {
                    self.floatingApproval = nil
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Composer(isDraftFocused: $isComposerFocused) { message in
                sentMessages.append(message)
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: floatingApproval?.id)
        .clawdiaScreenBackground()
        .chatNavigationChrome()
        .toolbar {
            if showsNavigationHeader {
                ToolbarItem(placement: .principal) {
                    Button {
                        showingAgentDetails = true
                    } label: {
                        ChatAgentNavigationTitle()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clawdia details")
                }
            }
        }
        .sheet(isPresented: $showingAgentDetails) {
            AgentDetailsSheet()
        }
    }
}

private struct ChatAgentNavigationTitle: View {
    @Environment(\.clawdiaTheme) private var theme

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        VStack(spacing: 1) {
            ClawdiaAvatar(size: 34)
            Text("Clawdia")
                .font(ClawdiaType.caption.weight(.semibold))
                .foregroundStyle(palette.text)
        }
        .frame(minWidth: 104, minHeight: 52)
        .contentShape(Rectangle())
    }
}

private struct AgentDetailsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.clawdiaTheme) private var theme

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        NavigationStack {
            VStack(spacing: ClawdiaSpacing.lg) {
                ClawdiaAvatar(size: 78)
                    .padding(.top, ClawdiaSpacing.lg)
                VStack(spacing: ClawdiaSpacing.xxs) {
                    Text("Clawdia")
                        .font(ClawdiaType.title)
                    Text("Personal agent")
                        .font(ClawdiaType.body)
                        .foregroundStyle(palette.text2)
                }
                ClawdiaCard {
                    VStack(alignment: .leading, spacing: ClawdiaSpacing.sm) {
                        StatusPill("Ready", systemImage: "checkmark.circle")
                        Text("Connected to local dev mode with chat, approvals, planning, and context surfaces available.")
                            .font(ClawdiaType.body)
                            .foregroundStyle(palette.text2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer()
            }
            .padding(ClawdiaSpacing.lg)
            .clawdiaScreenBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func chatNavigationChrome() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

private struct MessageBubble: View {
    @Environment(\.clawdiaTheme) private var theme
    let message: String
    let fromMe: Bool

    init(_ message: String, fromMe: Bool) {
        self.message = message
        self.fromMe = fromMe
    }

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        HStack {
            if fromMe { Spacer(minLength: 48) }
            Text(message)
                .font(ClawdiaType.body)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(fromMe ? palette.bubbleMeBackground : palette.bubbleThemBackground)
                .foregroundStyle(fromMe ? palette.bubbleMeForeground : palette.bubbleThemForeground)
                .clipShape(RoundedRectangle(cornerRadius: ClawdiaRadius.xl, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: ClawdiaRadius.xl, style: .continuous)
                        .stroke(fromMe ? palette.bubbleMeBackground : palette.border, lineWidth: 0.5)
                }
            if !fromMe { Spacer(minLength: 48) }
        }
    }
}

private struct ToolUseInline: View {
    @Environment(\.clawdiaTheme) private var theme

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        ClawdiaCard {
            HStack(spacing: ClawdiaSpacing.sm) {
                ProgressView()
                    .tint(palette.accent)
                VStack(alignment: .leading) {
                    Text("Looking at past notes about Mia")
                        .font(ClawdiaType.caption.weight(.semibold))
                    Text("Searching - Drafting")
                        .font(ClawdiaType.caption)
                        .foregroundStyle(palette.text2)
                }
            }
        }
    }
}

private struct ApprovalCard: View {
    @Environment(\.clawdiaTheme) private var theme
    let request: ApprovalRequest

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        ClawdiaCard {
            VStack(alignment: .leading, spacing: ClawdiaSpacing.sm) {
                Label(request.title, systemImage: "checkmark.seal")
                    .font(ClawdiaType.label)
                    .foregroundStyle(palette.accent)
                Text(request.detail)
                    .font(ClawdiaType.body)
                ClawdiaPillButton(request.primaryAction, systemImage: "checkmark")
                ClawdiaPillButton(request.secondaryAction, kind: .soft)
            }
        }
    }
}

private struct TodoCard: View {
    var body: some View {
        RichDataCard(title: "Lisbon trip - to-do", systemImage: "checklist") {
            ForEach(["Pack passport + adapter", "Hold mail", "Email Mia revised itinerary", "Confirm pickup"], id: \.self) { item in
                Label(item, systemImage: item == "Email Mia revised itinerary" ? "circle" : "checkmark.square.fill")
                    .font(ClawdiaType.caption)
            }
        }
    }
}

private struct FinanceCard: View {
    var body: some View {
        RichDataCard(title: "This week - spending", systemImage: "creditcard") {
            Text("$343")
                .font(ClawdiaType.display(32))
            Text("-$14 vs last week")
                .font(ClawdiaType.caption)
            ForEach(["Groceries $182", "Dining out $94", "Subscriptions $67"], id: \.self) { line in
                Text(line)
                    .font(ClawdiaType.caption)
            }
        }
    }
}

private struct StockCard: View {
    @Environment(\.clawdiaTheme) private var theme

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        RichDataCard(title: "NVDA - watchlist", systemImage: "chart.line.uptrend.xyaxis") {
            Text("$847.30")
                .font(ClawdiaType.display(28))
            GeometryReader { proxy in
                Path { path in
                    let points: [CGFloat] = [0.2, 0.35, 0.3, 0.5, 0.62, 0.55, 0.74, 0.68, 0.88]
                    for (index, point) in points.enumerated() {
                        let x = proxy.size.width * CGFloat(index) / CGFloat(points.count - 1)
                        let y = proxy.size.height * (1 - point)
                        if index == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(palette.success, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            .frame(height: 70)
        }
    }
}

struct RichDataCard<Content: View>: View {
    @Environment(\.clawdiaTheme) private var theme
    let title: String
    let systemImage: String
    let content: Content

    init(title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        ClawdiaCard {
            VStack(alignment: .leading, spacing: ClawdiaSpacing.xs) {
                Label(title, systemImage: systemImage)
                    .font(ClawdiaType.label)
                    .foregroundStyle(palette.accent)
                content
            }
        }
    }
}

private struct Composer: View {
    @Environment(\.clawdiaTheme) private var theme
    @State private var draft = ""
    let isDraftFocused: FocusState<Bool>.Binding
    let onSend: (String) -> Void

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        HStack(alignment: .center, spacing: ClawdiaSpacing.xs) {
            if #available(iOS 26.0, macOS 26.0, *) {
                GlassEffectContainer(spacing: ClawdiaSpacing.xs) {
                    HStack(alignment: .center, spacing: ClawdiaSpacing.xs) {
                        plusButton(palette)
                            .background(.ultraThinMaterial, in: Circle())
                            .glassEffect(.clear.interactive(), in: Circle())
                        textEntrySurface(palette)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay {
                                Capsule()
                                    .stroke(palette.border.opacity(0.9), lineWidth: 0.5)
                            }
                            .glassEffect(.clear.interactive(), in: Capsule())
                    }
                }
            } else {
                plusButton(palette)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay {
                        Circle()
                            .stroke(palette.border, lineWidth: 0.5)
                    }
                textEntrySurface(palette)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay {
                        Capsule()
                            .stroke(palette.border, lineWidth: 0.5)
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, ClawdiaSpacing.lg)
        .padding(.top, ClawdiaSpacing.xxs)
        .padding(.bottom, -1)
        .animation(.spring(response: 0.22, dampingFraction: 0.84), value: canSend)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func plusButton(_ palette: ClawdiaPalette) -> some View {
        Button {
        } label: {
            Image(systemName: "plus")
                .font(ClawdiaType.subhead.weight(.regular))
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.text)
    }

    private func textEntrySurface(_ palette: ClawdiaPalette) -> some View {
        HStack(spacing: ClawdiaSpacing.xs) {
            TextField("Message Clawdia", text: $draft)
                .focused(isDraftFocused)
                .font(ClawdiaType.body)
                .foregroundStyle(palette.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .padding(.horizontal, ClawdiaSpacing.xxs)
                .submitLabel(.send)
                .onSubmit(send)

            if canSend {
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(ClawdiaType.caption.weight(.bold))
                        .frame(width: 32, height: 32)
                        .background(palette.accent)
                        .foregroundStyle(palette.bubbleMeForeground)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .transition(.scale(scale: 0.82, anchor: .trailing).combined(with: .opacity))
            } else {
                Image(systemName: "waveform")
                    .font(ClawdiaType.subhead)
                    .foregroundStyle(palette.text2)
                    .frame(width: 34, height: 34)
            }
        }
        .padding(.leading, ClawdiaSpacing.xs)
        .padding(.trailing, 7)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, minHeight: 42)
    }

    private func send() {
        let message = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            return
        }
        onSend(message)
        draft = ""
    }
}

public struct VoiceScreen: View {
    @Environment(\.clawdiaTheme) private var theme
    public init() {}

    public var body: some View {
        let palette = ClawdiaColor.palette(theme)
        VStack(spacing: 0) {
            HStack {
                Text("Voice with Clawdia")
                    .font(ClawdiaType.label)
                    .foregroundStyle(palette.text2)
                Spacer()
                Text("00:42")
                    .font(ClawdiaType.mono)
                    .foregroundStyle(palette.text2)
            }
            .padding(.horizontal, ClawdiaSpacing.lg)
            .padding(.top, ClawdiaSpacing.lg)

            Spacer()

            Text("tell me what's on the calendar after lunch - and move my 4pm if it's that")
                .font(ClawdiaType.title)
                .foregroundStyle(palette.text)
                .multilineTextAlignment(.center)
                .padding(.horizontal, ClawdiaSpacing.lg)

            Spacer()

            Waveform()
                .padding(.bottom, ClawdiaSpacing.md)

            HStack(spacing: ClawdiaSpacing.xl) {
                CircleControl(systemImage: "text.bubble")
                CircleControl(systemImage: "stop.fill", large: true)
                CircleControl(systemImage: "xmark")
            }
            .padding(.bottom, 100)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clawdiaScreenBackground()
    }
}

private struct Waveform: View {
    @Environment(\.clawdiaTheme) private var theme

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        HStack(alignment: .center, spacing: 4) {
            ForEach(0..<28, id: \.self) { index in
                Capsule()
                    .fill(palette.accent)
                    .frame(width: 4, height: CGFloat(12 + (index * 13) % 72))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, ClawdiaSpacing.xl)
    }
}

private struct CircleControl: View {
    @Environment(\.clawdiaTheme) private var theme
    let systemImage: String
    var large = false

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        Image(systemName: systemImage)
            .font(large ? ClawdiaType.title : ClawdiaType.subhead)
            .frame(width: large ? 78 : 56, height: large ? 78 : 56)
            .background(large ? palette.text : palette.surface)
            .foregroundStyle(large ? palette.background : palette.text2)
            .clipShape(Circle())
    }
}

public struct ApprovalsGallery: View {
    let approvals: [ApprovalRequest]

    public init(approvals: [ApprovalRequest] = MockAppState.preview.approvals) {
        self.approvals = approvals
    }

    public var body: some View {
        FloatingApprovalDemo(approvals: approvals)
    }
}

private struct DiffPreview: View {
    let title: String
    let detail: String

    var bodyView: some View {
        RichDataCard(title: title, systemImage: "doc.text.magnifyingglass") {
            Text(detail)
                .font(ClawdiaType.body)
            HStack {
                ClawdiaPillButton("Accept", systemImage: "checkmark")
                ClawdiaPillButton("Review", kind: .soft)
            }
        }
    }

    var body: some View {
        bodyView
    }
}

private struct ToolUseReceipt: View {
    var body: some View {
        RichDataCard(title: "Agent activity", systemImage: "list.bullet.rectangle") {
            ForEach(["Searching notes", "Reading 3 chats", "Drafting card", "Checking tone", "Saving draft"], id: \.self) { step in
                Label(step, systemImage: "checkmark.circle.fill")
                    .font(ClawdiaType.caption)
            }
        }
    }
}

public struct SearchScreen: View {
    @Environment(\.clawdiaTheme) private var theme
    let state: MockAppState
    let onBack: () -> Void
    @State private var query = "flight to lisbon"
    @FocusState private var isSearchFocused: Bool

    public init(state: MockAppState = .preview, onBack: @escaping () -> Void = {}) {
        self.state = state
        self.onBack = onBack
    }

    public var body: some View {
        let palette = ClawdiaColor.palette(theme)
        VStack(spacing: 0) {
            HStack(spacing: ClawdiaSpacing.sm) {
                Button("Cancel", action: onBack)
                    .font(ClawdiaType.body)
                    .foregroundStyle(palette.accent)
                    .buttonStyle(.plain)
                SearchField(query: $query, isFocused: $isSearchFocused)
            }
            .padding(.horizontal, ClawdiaSpacing.lg)
            .padding(.top, ClawdiaSpacing.lg)
            .padding(.bottom, ClawdiaSpacing.md)
            .background(palette.background)

            ScrollView {
                VStack(alignment: .leading, spacing: ClawdiaSpacing.lg) {
                    ClawdiaSection("Top results") {
                        VStack(spacing: ClawdiaSpacing.xs) {
                            ForEach(filteredResults) { result in
                                SearchResult(result: result, query: query)
                            }
                            if filteredResults.isEmpty {
                                EmptySearchResult(query: query)
                            }
                        }
                    }
                    ClawdiaSection("Suggested") {
                        TagCloud(tags: ["flight prices", "lisbon weather", "AirBnB Alfama", "pack list"])
                    }
                }
                .padding(.horizontal, ClawdiaSpacing.lg)
                .padding(.bottom, 112)
                .frame(maxWidth: 520, alignment: .topLeading)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture {
                isSearchFocused = false
            }
        }
        .background(palette.background)
    }

    private var filteredResults: [SearchRecord] {
        let terms = searchTerms
        guard !terms.isEmpty else {
            return records
        }
        return records.filter { result in
            let text = result.searchText.lowercased()
            return terms.allSatisfy { text.contains($0) }
        }
    }

    private var searchTerms: [String] {
        let stopWords: Set<String> = ["a", "an", "and", "for", "in", "of", "on", "the", "to"]
        return query
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !stopWords.contains($0) }
    }

    private var records: [SearchRecord] {
        let chatRecords = state.chats.map { chat in
            SearchRecord(
                scope: "\(chat.area.rawValue.capitalized) - \(chat.title)",
                title: chat.preview,
                date: chat.time,
                detail: chat.preview,
                source: chat.title
            )
        }
        return chatRecords + [
            SearchRecord(
                scope: "Personal - Mia's birthday",
                title: "flight arrives Saturday morning, can pick her up before brunch",
                date: "Mar 22",
                detail: "Mia asked about arrival timing and the brunch plan.",
                source: "Messages"
            ),
            SearchRecord(
                scope: "Money - Travel budget",
                title: "Lisbon trip estimate: $1,840 incl. flights, lodging 4 nights, food $80/day",
                date: "Mar 18",
                detail: "Budget note from the Lisbon planning thread.",
                source: "Finance"
            )
        ]
    }
}

private struct SearchResult: View {
    @Environment(\.clawdiaTheme) private var theme
    let result: SearchRecord
    let query: String

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        VStack(alignment: .leading, spacing: ClawdiaSpacing.xs) {
            HStack {
                Text(result.scope.uppercased())
                    .font(ClawdiaType.label)
                    .foregroundStyle(palette.accent)
                Spacer()
                Text(result.date.uppercased())
                    .font(ClawdiaType.label)
                    .foregroundStyle(palette.text3)
            }
            Text(result.title)
                .font(ClawdiaType.body)
                .foregroundStyle(palette.text)
                .lineLimit(3)
            Text(result.source)
                .font(ClawdiaType.caption)
                .foregroundStyle(palette.text2)
        }
        .padding(ClawdiaSpacing.sm)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: ClawdiaRadius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ClawdiaRadius.lg, style: .continuous)
                .stroke(palette.border, lineWidth: 0.5)
        }
    }
}

private struct SearchField: View {
    @Environment(\.clawdiaTheme) private var theme
    @Binding var query: String
    let isFocused: FocusState<Bool>.Binding

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        HStack(spacing: ClawdiaSpacing.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(palette.text3)
            TextField("Search messages", text: $query)
                .focused(isFocused)
                .autocorrectionDisabled(true)
                .font(ClawdiaType.body)
                .foregroundStyle(palette.text)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(palette.text3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, ClawdiaSpacing.sm)
        .padding(.vertical, 10)
        .background(palette.surface2)
        .clipShape(RoundedRectangle(cornerRadius: ClawdiaRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ClawdiaRadius.md, style: .continuous)
                .stroke(palette.border, lineWidth: 0.5)
        }
    }
}

private struct EmptySearchResult: View {
    @Environment(\.clawdiaTheme) private var theme
    let query: String

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        ClawdiaCard {
            VStack(alignment: .leading, spacing: ClawdiaSpacing.xs) {
                Text("No results")
                    .font(ClawdiaType.body.weight(.semibold))
                Text("Nothing matched \"\(query)\" in the demo messages.")
                    .font(ClawdiaType.body)
                    .foregroundStyle(palette.text2)
            }
        }
    }
}

private struct SearchRecord: Identifiable {
    let id = UUID()
    let scope: String
    let title: String
    let date: String
    let detail: String
    let source: String

    var searchText: String {
        [scope, title, detail, source].joined(separator: " ")
    }
}

private struct TagCloud: View {
    @Environment(\.clawdiaTheme) private var theme
    let tags: [String]

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        FlowLayout(spacing: ClawdiaSpacing.xs) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(ClawdiaType.caption)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(palette.surface)
                    .clipShape(Capsule())
            }
        }
    }
}

public struct CalendarScreen: View {
    @Environment(\.clawdiaTheme) private var theme
    @State private var view = "Week"
    @State private var selectedDayID: String
    @State private var selectedMonthKey: String
    @State private var selectedWeekIndex = 1
    @State private var didSeedCalendar = false
    private let weeks = CalendarDemoData.weeks
    private let tasks = CalendarDemoData.tasks

    public init() {
        let initialDay = CalendarDemoData.initialSelectedDayID
        _selectedDayID = State(initialValue: initialDay)
        _selectedMonthKey = State(initialValue: CalendarDemoData.monthKey(for: initialDay) ?? "may")
        _selectedWeekIndex = State(initialValue: CalendarDemoData.weekIndex(for: initialDay))
    }

    public var body: some View {
        let palette = ClawdiaColor.palette(theme)
        let modes = ["Week", "Month", "Year"]
        let selectedWeek = weeks.indices.contains(selectedWeekIndex) ? weeks[selectedWeekIndex] : weeks[0]
        let selectedDay = CalendarDemoData.day(with: selectedDayID, in: weeks) ?? selectedWeek.days[0]
        GeometryReader { proxy in
            VStack(spacing: 0) {
                CalendarPinnedHeader(
                    view: $view,
                    modes: modes,
                    week: selectedWeek,
                    topPadding: max(proxy.safeAreaInsets.top + ClawdiaSpacing.sm, ClawdiaSpacing.xl * 2)
                )
                ScrollView {
                    VStack(alignment: .leading, spacing: ClawdiaSpacing.lg) {
                        if view == "Week" {
                            ScheduledTaskList(
                                weeks: weeks,
                                week: selectedWeek,
                                tasks: tasks,
                                selectedDay: selectedDay,
                                selectedDayID: $selectedDayID,
                                selectedWeekIndex: $selectedWeekIndex
                            )
                        } else if view == "Month" {
                            MonthCalendarView(
                                weeks: weeks,
                                tasks: tasks,
                                selectedDay: selectedDay,
                                selectedDayID: $selectedDayID,
                                selectedWeekIndex: $selectedWeekIndex
                            )
                        } else {
                            YearCalendarView(
                                weeks: weeks,
                                tasks: tasks,
                                selectedMonthKey: $selectedMonthKey,
                                selectedDayID: $selectedDayID,
                                selectedWeekIndex: $selectedWeekIndex
                            )
                        }
                    }
                    .padding(.horizontal, ClawdiaSpacing.lg)
                    .padding(.bottom, 92)
                    .frame(maxWidth: 520, alignment: .topLeading)
                    .frame(maxWidth: .infinity)
                }
            }
            .background(palette.background)
            .ignoresSafeArea(.container, edges: .top)
        }
        .background(palette.background)
        .onChange(of: selectedWeekIndex) { _, newIndex in
            let week = weeks[newIndex]
            if !week.days.contains(where: { $0.id == selectedDayID }) {
                selectedDayID = week.highlightDayID
            }
        }
        .onChange(of: selectedDayID) { _, newValue in
            selectedWeekIndex = CalendarDemoData.weekIndex(for: newValue)
            selectedMonthKey = CalendarDemoData.monthKey(for: newValue) ?? selectedMonthKey
        }
        .onAppear {
            seedCalendarSelectionIfNeeded()
        }
    }

    private func seedCalendarSelectionIfNeeded() {
        guard !didSeedCalendar else {
            return
        }
        didSeedCalendar = true
        let initialDay = CalendarDemoData.initialSelectedDayID
        selectedDayID = initialDay
        selectedMonthKey = CalendarDemoData.monthKey(for: initialDay) ?? selectedMonthKey
        selectedWeekIndex = CalendarDemoData.weekIndex(for: initialDay)
    }
}

private struct CalendarPinnedHeader: View {
    @Environment(\.clawdiaTheme) private var theme
    @Binding var view: String
    let modes: [String]
    let week: CalendarWeek
    let topPadding: CGFloat

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        VStack(alignment: .leading, spacing: ClawdiaSpacing.xs) {
            CalendarTitle(
                mode: view,
                week: week
            )
            Picker("Calendar view", selection: $view) {
                ForEach(modes, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, ClawdiaSpacing.lg)
        .padding(.top, topPadding)
        .padding(.bottom, ClawdiaSpacing.sm)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: 520, alignment: .topLeading)
        .frame(maxWidth: .infinity)
        .background {
            Rectangle()
                .fill(palette.background)
        }
        .zIndex(2)
    }
}

private struct CalendarWeek: Identifiable, Equatable {
    let id: String
    let eyebrow: String
    let month: String
    let startDay: Int
    let endMonth: String?
    let endDay: Int
    let days: [CalendarDay]
    let highlightDayID: String

    var rangeText: String {
        if let endMonth, endMonth != month {
            return "\(startDay) - \(endMonth) \(endDay)"
        }
        return "\(startDay) - \(endDay)"
    }

}

private struct CalendarDay: Identifiable, Equatable {
    let id: String
    let taskDayID: String
    let weekday: String
    let year: Int
    let monthNumber: Int
    let monthKey: String
    let month: String
    let displayDay: Int
    let hasMarker: Bool
}

private enum CalendarDemoData {
    static let year = 2026

    static var initialSelectedDayID: String {
        dayID(for: Date()) ?? tasks.first?.dayID ?? allDays.first?.id ?? ""
    }

    static let tasks: [ScheduledTask] = [
        ScheduledTask(id: "may-7-recap", dayID: "may-7", time: "9:00 AM", title: "Send weekly recap to Marcus", context: "Work", status: .done, note: "Drafted, sent at 8:58 AM"),
        ScheduledTask(id: "may-7-flights", dayID: "may-7", time: "11:30 AM", title: "Watch flight prices to Lisbon", context: "Travel", status: .running, note: "Checking 3 airlines hourly"),
        ScheduledTask(id: "may-7-expense", dayID: "may-7", time: "2:00 PM", title: "Pull Q1 expense breakdown", context: "Money", status: .waiting, note: "Waiting for your approval"),
        ScheduledTask(id: "may-7-call", dayID: "may-7", time: "6:30 PM", title: "Remind to call Mom", context: "Personal", status: .upcoming, note: nil),
        ScheduledTask(id: "may-8-briefing", dayID: "may-8", time: "8:00 AM", title: "Morning briefing", context: "Personal", status: .upcoming, note: nil),
        ScheduledTask(id: "may-6-review", dayID: "may-6", time: "3:00 PM", title: "Review design crit notes", context: "Work", status: .done, note: "Summary ready"),
        ScheduledTask(id: "may-9-pack", dayID: "may-9", time: "10:00 AM", title: "Lisbon packing list", context: "Travel", status: .upcoming, note: "Weather checked"),
        ScheduledTask(id: "may-13-checkin", dayID: "may-13", time: "1:30 PM", title: "Quarterly tax check-in", context: "Money", status: .waiting, note: "Needs approval"),
        ScheduledTask(id: "may-21-demo", dayID: "may-21", time: "12:00 PM", title: "Demo app walkthrough", context: "Work", status: .upcoming, note: "Components ready"),
        ScheduledTask(id: "may-28-renewal", dayID: "may-28", time: "5:00 PM", title: "Card renewal reminder", context: "Money", status: .waiting, note: "Approval needed"),
        ScheduledTask(id: "apr-29-cleanup", dayID: "apr-29", time: "4:00 PM", title: "Archive stale chats", context: "Personal", status: .done, note: nil),
        ScheduledTask(id: "may-2-birthday", dayID: "may-2", time: "9:30 AM", title: "Mia birthday card", context: "Personal", status: .done, note: "Draft saved")
    ]

    static let weeks: [CalendarWeek] = makeWeeks()

    static let months: [CalendarMonth] = (1...12).map { monthNumber in
        CalendarMonth(key: monthKey(forMonthNumber: monthNumber), title: monthTitle(forMonthNumber: monthNumber))
    }

    static var allDays: [CalendarDay] {
        weeks.flatMap(\.days)
    }

    static func day(with id: String, in weeks: [CalendarWeek]) -> CalendarDay? {
        weeks.flatMap(\.days).first { $0.id == id }
    }

    static func weekIndex(for dayID: String) -> Int {
        weeks.firstIndex { week in
            week.days.contains { $0.id == dayID || $0.taskDayID == dayID }
        } ?? 0
    }

    static func monthKey(for dayID: String) -> String? {
        allDays.first { $0.id == dayID || $0.taskDayID == dayID }?.monthKey
    }

    static func dayID(for date: Date) -> String? {
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        let monthKey = monthKey(forMonthNumber: month)
        let id = "\(year)-\(monthKey)-\(day)"
        return allDays.contains { $0.id == id } ? id : nil
    }

    static func tasks(on dayID: String, from tasks: [ScheduledTask]) -> [ScheduledTask] {
        let taskDayID = allDays.first { $0.id == dayID || $0.taskDayID == dayID }?.taskDayID ?? dayID
        return tasks.filter { $0.dayID == taskDayID }
    }

    static func nextDay(after dayID: String) -> CalendarDay? {
        guard let index = allDays.firstIndex(where: { $0.id == dayID || $0.taskDayID == dayID }),
              allDays.indices.contains(index + 1) else {
            return nil
        }
        return allDays[index + 1]
    }

    static func firstDayID(in monthKey: String) -> String? {
        allDays.first { $0.monthKey == monthKey }?.id
    }

    static func days(in monthKey: String) -> [CalendarDay] {
        allDays.filter { $0.year == year && $0.monthKey == monthKey }
    }

    static func leadingBlankCount(for monthKey: String) -> Int {
        guard let firstDay = days(in: monthKey).first,
              let date = makeDate(year: firstDay.year, month: firstDay.monthNumber, day: firstDay.displayDay) else {
            return 0
        }
        let weekday = calendar.component(.weekday, from: date)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        return calendar
    }()

    private static func makeWeeks() -> [CalendarWeek] {
        guard let yearStart = makeDate(year: year, month: 1, day: 1),
              let yearEnd = makeDate(year: year, month: 12, day: 31),
              let firstWeek = calendar.dateInterval(of: .weekOfYear, for: yearStart),
              let lastWeek = calendar.dateInterval(of: .weekOfYear, for: yearEnd) else {
            return []
        }
        let taskDayIDs = Set(tasks.map(\.dayID))
        var weekStart = firstWeek.start
        var result: [CalendarWeek] = []
        while weekStart <= lastWeek.start {
            let days = (0..<7).compactMap { offset in
                calendar.date(byAdding: .day, value: offset, to: weekStart).map {
                    makeDay(from: $0, taskDayIDs: taskDayIDs)
                }
            }
            if let firstDay = days.first, let lastDay = days.last {
                result.append(
                    CalendarWeek(
                        id: "\(firstDay.id)-\(lastDay.id)",
                        eyebrow: eyebrow(for: weekStart),
                        month: firstDay.month,
                        startDay: firstDay.displayDay,
                        endMonth: lastDay.month,
                        endDay: lastDay.displayDay,
                        days: days,
                        highlightDayID: days.first(where: { taskDayIDs.contains($0.taskDayID) })?.id ?? days[0].id
                    )
                )
            }
            guard let nextWeek = calendar.date(byAdding: .day, value: 7, to: weekStart) else {
                break
            }
            weekStart = nextWeek
        }
        return result
    }

    private static func makeDay(from date: Date, taskDayIDs: Set<String>) -> CalendarDay {
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let day = calendar.component(.day, from: date)
        let key = monthKey(forMonthNumber: month)
        let taskDayID = "\(key)-\(day)"
        return CalendarDay(
            id: "\(year)-\(taskDayID)",
            taskDayID: taskDayID,
            weekday: weekdayTitle(for: date),
            year: year,
            monthNumber: month,
            monthKey: key,
            month: monthTitle(forMonthNumber: month),
            displayDay: day,
            hasMarker: taskDayIDs.contains(taskDayID)
        )
    }

    private static func eyebrow(for weekStart: Date) -> String {
        guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: Date()) else {
            return "This week"
        }
        if calendar.isDate(weekStart, inSameDayAs: currentWeek.start) {
            return "This week"
        }
        if weekStart < currentWeek.start {
            return "Earlier"
        }
        return "Later"
    }

    private static func weekdayTitle(for date: Date) -> String {
        switch calendar.component(.weekday, from: date) {
        case 1: return "S"
        case 2: return "M"
        case 3: return "T"
        case 4: return "W"
        case 5: return "T"
        case 6: return "F"
        default: return "S"
        }
    }

    private static func makeDate(year: Int, month: Int, day: Int) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    private static func monthKey(forMonthNumber month: Int) -> String {
        monthKeys[max(0, min(month - 1, 11))]
    }

    private static func monthTitle(forMonthNumber month: Int) -> String {
        monthTitles[max(0, min(month - 1, 11))]
    }

    private static let monthKeys = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
    private static let monthTitles = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
}

private struct CalendarTitle: View {
    @Environment(\.clawdiaTheme) private var theme
    let mode: String
    let week: CalendarWeek

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        VStack(alignment: .leading, spacing: ClawdiaSpacing.xxs) {
            Text(mode == "Year" ? "This year" : mode == "Month" ? "This month" : week.eyebrow)
                .font(ClawdiaType.caption.weight(.medium))
                .foregroundStyle(palette.text2)
            HStack(spacing: ClawdiaSpacing.xs) {
                if mode == "Year" {
                    Text("20")
                    Text("26")
                        .foregroundStyle(palette.accent)
                } else if mode == "Month" {
                    Text("May")
                    Text("2026")
                        .foregroundStyle(palette.accent)
                } else {
                    Text(week.month)
                    Text("\(week.startDay)")
                        .foregroundStyle(palette.accent)
                    Text("- \(week.endMonth.map { "\($0) " } ?? "")\(week.endDay)")
                }
            }
            .font(ClawdiaType.display())
            .foregroundStyle(palette.text)
            .contentTransition(.numericText())
        }
    }
}

private struct WeekNavigationButton: View {
    @Environment(\.clawdiaTheme) private var theme
    let systemImage: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        Button(action: action) {
            Image(systemName: systemImage)
                .font(ClawdiaType.label.weight(.semibold))
                .frame(width: 32, height: 32)
                .foregroundStyle(enabled ? palette.text : palette.text3.opacity(0.52))
                .background(enabled ? palette.surface : .clear)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

private struct ScheduledTaskList: View {
    let weeks: [CalendarWeek]
    let week: CalendarWeek
    let tasks: [ScheduledTask]
    let selectedDay: CalendarDay
    @Binding var selectedDayID: String
    @Binding var selectedWeekIndex: Int

    var body: some View {
        VStack(spacing: ClawdiaSpacing.sm) {
            WeekStrip(
                weeks: weeks,
                week: week,
                selectedDayID: $selectedDayID,
                selectedWeekIndex: $selectedWeekIndex
            )
            SelectedDayTaskSection(
                title: selectedDayTitle,
                tasks: CalendarDemoData.tasks(on: selectedDayID, from: tasks)
            )
            if let nextDay = CalendarDemoData.nextDay(after: selectedDayID) {
                SelectedDayTaskSection(
                    title: nextDay.month == selectedDay.month ? "Next day" : "\(nextDay.month) \(nextDay.displayDay)",
                    tasks: CalendarDemoData.tasks(on: nextDay.id, from: tasks)
                )
            }
        }
    }

    private var selectedDayTitle: String {
        selectedDay.id == CalendarDemoData.initialSelectedDayID ? "Today - Clawdia is on it" : "\(selectedDay.month) \(selectedDay.displayDay)"
    }
}

private struct SelectedDayTaskSection: View {
    let title: String
    let tasks: [ScheduledTask]

    var body: some View {
        ClawdiaSection(title) {
            VStack(spacing: ClawdiaSpacing.xs) {
                if tasks.isEmpty {
                    EmptyScheduleCard()
                } else {
                    ForEach(tasks) { task in
                        ScheduledTaskCard(task: task)
                    }
                }
            }
        }
    }
}

private struct EmptyScheduleCard: View {
    @Environment(\.clawdiaTheme) private var theme

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        HStack(spacing: ClawdiaSpacing.sm) {
            Image(systemName: "moon.zzz")
                .font(ClawdiaType.subhead)
                .frame(width: 30, height: 30)
                .foregroundStyle(palette.text3)
                .background(palette.surface2)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: ClawdiaSpacing.xxs) {
                Text("No scheduled tasks")
                    .font(ClawdiaType.body.weight(.semibold))
                    .foregroundStyle(palette.text)
                Text("Clawdia is keeping this day clear.")
                    .font(ClawdiaType.caption)
                    .foregroundStyle(palette.text2)
            }
            Spacer()
        }
        .padding(ClawdiaSpacing.sm)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: ClawdiaRadius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ClawdiaRadius.lg, style: .continuous)
                .stroke(palette.border, lineWidth: 0.5)
        }
    }
}

private struct WeekStrip: View {
    @Environment(\.clawdiaTheme) private var theme
    let weeks: [CalendarWeek]
    let week: CalendarWeek
    @Binding var selectedDayID: String
    @Binding var selectedWeekIndex: Int
    @State private var hasSeededScrollPosition = false
    @State private var pendingSettledItemID: String?
    @State private var settleTask: Task<Void, Never>?
    @State private var isUpdatingSelectionFromScroll = false
    private let coordinateSpaceName = "calendar-week-strip"

    var body: some View {
        GeometryReader { proxy in
            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal) {
                    HStack(spacing: ClawdiaSpacing.sm) {
                        ForEach(carouselItems) { item in
                            WeekDayPill(
                                day: item.day.weekday,
                                date: item.day.displayDay,
                                active: item.day.id == selectedDayID,
                                hasDot: item.day.hasMarker,
                                prominence: prominence(for: item),
                                width: pillWidth(in: proxy.size.width)
                            ) {
                                select(item, scrollProxy: scrollProxy)
                            }
                            .id(item.id)
                            .background {
                                GeometryReader { itemProxy in
                                    Color.clear.preference(
                                        key: WeekStripItemFramePreferenceKey.self,
                                        value: [item.id: itemProxy.frame(in: .named(coordinateSpaceName))]
                                    )
                                }
                            }
                            .zIndex(Double(prominence(for: item)))
                        }
                    }
                }
                .coordinateSpace(name: coordinateSpaceName)
                .contentMargins(.horizontal, horizontalInset(for: proxy.size.width), for: .scrollContent)
                .scrollIndicators(.hidden)
                .onAppear {
                    seedScrollPosition(scrollProxy)
                }
                .onChange(of: selectedDayID) { _, newValue in
                    guard !isUpdatingSelectionFromScroll else {
                        return
                    }
                    centerSelectedDay(newValue, scrollProxy: scrollProxy)
                }
                .onPreferenceChange(WeekStripItemFramePreferenceKey.self) { frames in
                    scheduleSelectionForNearestItem(in: frames, viewportWidth: proxy.size.width)
                }
            }
        }
        .frame(height: 84)
        .padding(.top, 0)
        .padding(.bottom, ClawdiaSpacing.xs)
        .onDisappear {
            settleTask?.cancel()
        }
    }

    private var carouselItems: [CalendarCarouselItem] {
        weeks.enumerated().flatMap { weekIndex, week in
            week.days.map { day in
                CalendarCarouselItem(day: day, weekIndex: weekIndex)
            }
        }
    }

    private func select(_ item: CalendarCarouselItem, scrollProxy: ScrollViewProxy) {
        settleTask?.cancel()
        pendingSettledItemID = item.id
        withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
            selectedDayID = item.day.id
            selectedWeekIndex = item.weekIndex
            scrollProxy.scrollTo(item.id, anchor: .center)
        }
    }

    private func seedScrollPosition(_ scrollProxy: ScrollViewProxy) {
        guard !hasSeededScrollPosition else {
            return
        }
        hasSeededScrollPosition = true
        DispatchQueue.main.async {
            scrollProxy.scrollTo(selectedDayID, anchor: .center)
        }
    }

    private func centerSelectedDay(_ dayID: String, scrollProxy: ScrollViewProxy) {
        guard hasSeededScrollPosition else {
            return
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
            scrollProxy.scrollTo(dayID, anchor: .center)
        }
    }

    private func scheduleSelectionForNearestItem(in frames: [String: CGRect], viewportWidth: CGFloat) {
        guard hasSeededScrollPosition else {
            return
        }
        let viewportCenter = viewportWidth / 2
        guard let nearest = frames.min(by: {
            abs($0.value.midX - viewportCenter) < abs($1.value.midX - viewportCenter)
        }) else {
            return
        }
        guard nearest.key != pendingSettledItemID else {
            return
        }
        pendingSettledItemID = nearest.key
        settleTask?.cancel()
        guard nearest.key != selectedDayID else {
            return
        }
        settleTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else {
                return
            }
            applySettledSelection(nearest.key)
        }
    }

    private func applySettledSelection(_ itemID: String) {
        guard pendingSettledItemID == itemID,
              let item = carouselItems.first(where: { $0.id == itemID }) else {
            return
        }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        isUpdatingSelectionFromScroll = true
        withTransaction(transaction) {
            selectedDayID = item.day.id
            selectedWeekIndex = item.weekIndex
        }
        DispatchQueue.main.async {
            isUpdatingSelectionFromScroll = false
        }
    }

    private func pillWidth(in containerWidth: CGFloat) -> CGFloat {
        let spacing = ClawdiaSpacing.sm * 4
        return min(66, max(56, (containerWidth - spacing) / 5))
    }

    private func horizontalInset(for containerWidth: CGFloat) -> CGFloat {
        max(ClawdiaSpacing.lg, (containerWidth - pillWidth(in: containerWidth)) / 2)
    }

    private func prominence(for item: CalendarCarouselItem) -> CGFloat {
        guard let selectedIndex = carouselItems.firstIndex(where: { $0.day.id == selectedDayID }),
              let itemIndex = carouselItems.firstIndex(where: { $0.id == item.id }) else {
            return 0
        }
        switch abs(itemIndex - selectedIndex) {
        case 0:
            return 1
        case 1:
            return 0.38
        case 2:
            return 0.16
        default:
            return 0
        }
    }
}

private struct WeekStripItemFramePreferenceKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct CalendarCarouselItem: Identifiable {
    let day: CalendarDay
    let weekIndex: Int

    var id: String { day.id }
}

private struct WeekDayPill: View {
    @Environment(\.clawdiaTheme) private var theme
    let day: String
    let date: Int
    let active: Bool
    let hasDot: Bool
    let prominence: CGFloat
    let width: CGFloat
    let onTap: () -> Void

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        let scale = 1 + prominence * 0.12
        Button(action: onTap) {
            ZStack {
                if active {
                    RoundedRectangle(cornerRadius: ClawdiaRadius.md, style: .continuous)
                        .fill(palette.text)
                        .shadow(color: palette.text.opacity(0.14), radius: 14, y: 7)
                } else {
                    RoundedRectangle(cornerRadius: ClawdiaRadius.md, style: .continuous)
                        .fill(palette.surface)
                        .overlay {
                            RoundedRectangle(cornerRadius: ClawdiaRadius.md, style: .continuous)
                                .stroke(palette.border, lineWidth: 0.5)
                        }
                }
                VStack(spacing: ClawdiaSpacing.xxs) {
                    Text(day)
                        .font(ClawdiaType.label)
                        .foregroundStyle(active ? palette.background.opacity(0.68) : palette.text2)
                    Text("\(date)")
                        .font(ClawdiaType.subhead)
                    Circle()
                        .fill(hasDot ? (active ? palette.background : palette.accent) : .clear)
                        .frame(width: 4, height: 4)
                }
                .foregroundStyle(active ? palette.background : palette.text)
            }
            .frame(width: width, height: 68)
        }
        .buttonStyle(.plain)
        .scaleEffect(scale)
        .offset(y: -prominence * 4)
        .animation(.spring(response: 0.28, dampingFraction: 0.76), value: prominence)
    }
}

private struct ScheduledTask: Identifiable {
    enum Status {
        case done
        case running
        case waiting
        case upcoming
    }

    let id: String
    let dayID: String
    let time: String
    let title: String
    let context: String
    let status: Status
    let note: String?
}

private struct ScheduledTaskCard: View {
    @Environment(\.clawdiaTheme) private var theme
    let task: ScheduledTask

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        HStack(alignment: .top, spacing: ClawdiaSpacing.sm) {
            StatusDot(status: task.status)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: ClawdiaSpacing.xxs) {
                HStack(alignment: .center, spacing: ClawdiaSpacing.xs) {
                    Text(task.title)
                        .font(ClawdiaType.body.weight(.semibold))
                        .foregroundStyle(palette.text)
                        .lineLimit(2)
                    Spacer()
                    Text(task.context)
                        .font(ClawdiaType.caption)
                        .foregroundStyle(palette.text3)
                }
                HStack(spacing: ClawdiaSpacing.xs) {
                    Text(task.time)
                        .font(ClawdiaType.label)
                        .foregroundStyle(palette.text2)
                    if let note = task.note {
                        Text(note)
                            .font(ClawdiaType.caption)
                            .foregroundStyle(palette.text2)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(ClawdiaSpacing.sm)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: ClawdiaRadius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ClawdiaRadius.lg, style: .continuous)
                .stroke(palette.border, lineWidth: 0.5)
        }
    }
}

private struct StatusDot: View {
    @Environment(\.clawdiaTheme) private var theme
    let status: ScheduledTask.Status

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        Image(systemName: symbol)
            .font(ClawdiaType.subhead.weight(.semibold))
            .foregroundStyle(color(palette))
            .frame(width: 30, height: 30)
            .background(color(palette).opacity(0.12))
            .clipShape(Circle())
            .shadow(color: status == .running ? color(palette).opacity(0.32) : .clear, radius: 8)
    }

    private var symbol: String {
        switch status {
        case .done: "checkmark.circle.fill"
        case .running: "circle.fill"
        case .waiting: "exclamationmark.circle.fill"
        case .upcoming: "circle"
        }
    }

    private func color(_ palette: ClawdiaPalette) -> Color {
        switch status {
        case .done: palette.success
        case .running: palette.accent
        case .waiting: palette.warn
        case .upcoming: palette.text3
        }
    }
}

private struct MonthCalendarView: View {
    let weeks: [CalendarWeek]
    let tasks: [ScheduledTask]
    let selectedDay: CalendarDay
    @Binding var selectedDayID: String
    @Binding var selectedWeekIndex: Int

    var body: some View {
        VStack(alignment: .leading, spacing: ClawdiaSpacing.md) {
            VStack(spacing: ClawdiaSpacing.xs) {
                HStack {
                    ForEach(Array(["M", "T", "W", "T", "F", "S", "S"].enumerated()), id: \.offset) { _, weekday in
                        Text(weekday)
                            .font(ClawdiaType.label)
                            .frame(maxWidth: .infinity)
                    }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: ClawdiaSpacing.xs), count: 7), spacing: ClawdiaSpacing.xs) {
                    ForEach(monthCells) { cell in
                        CalendarCell(
                            day: cell.day?.displayDay,
                            active: cell.day?.id == selectedDayID,
                            hasTasks: cell.day.map { CalendarDemoData.tasks(on: $0.id, from: tasks).isEmpty == false } ?? false
                        ) {
                            guard let day = cell.day else {
                                return
                            }
                            select(day)
                        }
                    }
                }
            }
            SelectedDayTaskSection(
                title: "\(selectedDay.month) \(selectedDay.displayDay)",
                tasks: CalendarDemoData.tasks(on: selectedDayID, from: tasks)
            )
        }
    }

    private var monthCells: [MonthCell] {
        let monthKey = selectedDay.monthKey
        let leadingBlanks = (0..<CalendarDemoData.leadingBlankCount(for: monthKey)).map {
            MonthCell(id: "blank-\(monthKey)-\($0)", day: nil)
        }
        return leadingBlanks + CalendarDemoData.days(in: monthKey).map { MonthCell(id: $0.id, day: $0) }
    }

    private func select(_ day: CalendarDay) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            selectedDayID = day.id
            selectedWeekIndex = CalendarDemoData.weekIndex(for: day.id)
        }
    }
}

private struct CalendarCell: View {
    @Environment(\.clawdiaTheme) private var theme
    let day: Int?
    let active: Bool
    let hasTasks: Bool
    let action: () -> Void

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        Button(action: action) {
            VStack(spacing: ClawdiaSpacing.xxs) {
                Text(day.map(String.init) ?? "")
                    .font(ClawdiaType.caption.weight(.semibold))
                Circle()
                    .fill(hasTasks ? (active ? palette.background : palette.accent) : .clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(active ? palette.text : day == nil ? Color.clear : palette.surface)
            .foregroundStyle(active ? palette.background : palette.text)
            .clipShape(RoundedRectangle(cornerRadius: ClawdiaRadius.md, style: .continuous))
            .overlay {
                if day != nil && !active {
                    RoundedRectangle(cornerRadius: ClawdiaRadius.md, style: .continuous)
                        .stroke(palette.border, lineWidth: 0.5)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(day == nil)
    }
}

private struct MonthCell: Identifiable {
    let id: String
    let day: CalendarDay?
}

private struct YearCalendarView: View {
    let weeks: [CalendarWeek]
    let tasks: [ScheduledTask]
    @Binding var selectedMonthKey: String
    @Binding var selectedDayID: String
    @Binding var selectedWeekIndex: Int

    var body: some View {
        VStack(alignment: .leading, spacing: ClawdiaSpacing.md) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: ClawdiaSpacing.xs), count: 3), spacing: ClawdiaSpacing.xs) {
                ForEach(CalendarDemoData.months) { month in
                    MonthTile(
                        month: month,
                        active: month.key == selectedMonthKey,
                        taskCount: taskCount(for: month.key)
                    ) {
                        select(month)
                    }
                }
            }
            SelectedDayTaskSection(
                title: selectedMonthTitle,
                tasks: tasks.filter { task in
                    CalendarDemoData.monthKey(for: task.dayID) == selectedMonthKey
                }
            )
        }
    }

    private var selectedMonthTitle: String {
        CalendarDemoData.months.first { $0.key == selectedMonthKey }?.title.appending(" highlights") ?? "Highlights"
    }

    private func select(_ month: CalendarMonth) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
            selectedMonthKey = month.key
            if let firstDayID = CalendarDemoData.firstDayID(in: month.key) {
                selectedDayID = firstDayID
                selectedWeekIndex = CalendarDemoData.weekIndex(for: firstDayID)
            }
        }
    }

    private func taskCount(for monthKey: String) -> Int {
        tasks.filter { CalendarDemoData.monthKey(for: $0.dayID) == monthKey }.count
    }

}

private struct CalendarMonth: Identifiable {
    let key: String
    let title: String

    var id: String { key }
}

private struct MonthTile: View {
    @Environment(\.clawdiaTheme) private var theme
    let month: CalendarMonth
    let active: Bool
    let taskCount: Int
    let action: () -> Void

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        Button(action: action) {
            VStack(alignment: .leading, spacing: ClawdiaSpacing.sm) {
                HStack {
                    Text(month.title)
                        .font(ClawdiaType.body.weight(.semibold))
                    Spacer()
                    if taskCount > 0 {
                        Circle()
                            .fill(active ? palette.background : palette.accent)
                            .frame(width: 6, height: 6)
                    }
                }
                Text(taskCount == 1 ? "1 task" : "\(taskCount) tasks")
                    .font(ClawdiaType.caption)
                    .foregroundStyle(active ? palette.background.opacity(0.72) : palette.text2)
            }
            .padding(ClawdiaSpacing.sm)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
            .background(active ? palette.text : palette.surface)
            .foregroundStyle(active ? palette.background : palette.text)
            .clipShape(RoundedRectangle(cornerRadius: ClawdiaRadius.lg, style: .continuous))
            .overlay {
                if !active {
                    RoundedRectangle(cornerRadius: ClawdiaRadius.lg, style: .continuous)
                        .stroke(palette.border, lineWidth: 0.5)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct Stat: View {
    let value: String
    let label: String

    init(_ value: String, _ label: String) {
        self.value = value
        self.label = label
    }

    var body: some View {
        VStack {
            Text(value)
                .font(ClawdiaType.display(26))
            Text(label.uppercased())
                .font(ClawdiaType.label)
        }
        .frame(maxWidth: .infinity)
    }
}

public struct FolderManagerScreen: View {
    @Environment(\.clawdiaTheme) private var theme
    let folders: [FolderSummary]
    let onDone: () -> Void
    @State private var customAreas: [CustomArea] = []
    @State private var showingNewArea = false
    @State private var draftAreaName = ""

    public init(folders: [FolderSummary] = MockAppState.preview.folders, onDone: @escaping () -> Void = {}) {
        self.folders = folders
        self.onDone = onDone
    }

    public var body: some View {
        let palette = ClawdiaColor.palette(theme)
        let visibleFolders = Array(folders.prefix(6))
        AppScroll {
            ManageAreasHeader(onDone: onDone) {
                showingNewArea = true
            }
            Text("Drag to reorder. Pinned areas appear first on home.")
                .font(ClawdiaType.caption)
                .foregroundStyle(palette.text2)
            VStack(spacing: ClawdiaSpacing.xs) {
                ForEach(Array(visibleFolders.enumerated()), id: \.element.id) { index, folder in
                    ManageAreaRow(folder: folder, colorIndex: index)
                }
                ForEach(Array(customAreas.enumerated()), id: \.element.id) { index, area in
                    ManageCustomAreaRow(area: area, colorIndex: index + visibleFolders.count)
                }
                NewAreaTile(title: "Create new area", subtitle: "Add a new life area", onTap: {
                    showingNewArea = true
                })
            }
        }
        .sheet(isPresented: $showingNewArea) {
            NewAreaSheet(name: $draftAreaName) {
                let name = draftAreaName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty {
                    customAreas.append(CustomArea(name: name))
                }
                draftAreaName = ""
                showingNewArea = false
            } onCancel: {
                draftAreaName = ""
                showingNewArea = false
            }
        }
    }
}

private struct ManageAreasHeader: View {
    @Environment(\.clawdiaTheme) private var theme
    let onDone: () -> Void
    let onAdd: () -> Void

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        HStack {
            Button("Done", action: onDone)
                .font(ClawdiaType.body)
                .foregroundStyle(palette.accent)
            Spacer()
            Text("Your areas")
                .font(ClawdiaType.body.weight(.semibold))
            Spacer()
            Button(action: onAdd) {
                Text("+ Add")
                    .font(ClawdiaType.body.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(palette.accent)
        }
    }
}

private struct ManageAreaRow: View {
    @Environment(\.clawdiaTheme) private var theme
    let folder: FolderSummary
    let colorIndex: Int

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        HStack(spacing: ClawdiaSpacing.sm) {
            Image(systemName: "circle.grid.2x2")
                .font(ClawdiaType.caption)
                .foregroundStyle(palette.text3)
            Image(systemName: folder.id.icon)
                .frame(width: 40, height: 40)
                .background(palette.folders[colorIndex % palette.folders.count])
                .clipShape(RoundedRectangle(cornerRadius: ClawdiaRadius.md, style: .continuous))
            VStack(alignment: .leading, spacing: ClawdiaSpacing.xxs) {
                Text(folder.id.title)
                    .font(ClawdiaType.body.weight(.semibold))
                Text("\(folder.chatCount) chats")
                    .font(ClawdiaType.caption)
                    .foregroundStyle(palette.text2)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(palette.text3)
        }
        .padding(ClawdiaSpacing.md)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: ClawdiaRadius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ClawdiaRadius.lg, style: .continuous)
                .stroke(palette.border, lineWidth: 0.5)
        }
    }
}

private struct ManageCustomAreaRow: View {
    @Environment(\.clawdiaTheme) private var theme
    let area: CustomArea
    let colorIndex: Int

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        HStack(spacing: ClawdiaSpacing.sm) {
            Image(systemName: "circle.grid.2x2")
                .font(ClawdiaType.caption)
                .foregroundStyle(palette.text3)
            Image(systemName: "sparkles")
                .frame(width: 40, height: 40)
                .background(palette.folders[colorIndex % palette.folders.count])
                .clipShape(RoundedRectangle(cornerRadius: ClawdiaRadius.md, style: .continuous))
            VStack(alignment: .leading, spacing: ClawdiaSpacing.xxs) {
                Text(area.name)
                    .font(ClawdiaType.body.weight(.semibold))
                Text("0 chats")
                    .font(ClawdiaType.caption)
                    .foregroundStyle(palette.text2)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(palette.text3)
        }
        .padding(ClawdiaSpacing.md)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: ClawdiaRadius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ClawdiaRadius.lg, style: .continuous)
                .stroke(palette.border, lineWidth: 0.5)
        }
    }
}

public struct SettingsScreen: View {
    @Binding private var theme: ClawdiaTheme
    private let onOpenAreas: () -> Void
    private let onOpenDevelopment: (DevScreen) -> Void

    public init(
        theme: Binding<ClawdiaTheme> = .constant(.light),
        onOpenAreas: @escaping () -> Void = {},
        onOpenDevelopment: @escaping (DevScreen) -> Void = { _ in }
    ) {
        _theme = theme
        self.onOpenAreas = onOpenAreas
        self.onOpenDevelopment = onOpenDevelopment
    }

    public var body: some View {
        AppScroll {
            Text("you")
                .font(ClawdiaType.display())
            ClawdiaProfileSettingsCard()
            ClawdiaSettingsSection(title: "Clawdia", rows: [
                SettingsRowData(icon: "◆", label: "Personality", detail: "Warm friend"),
                SettingsRowData(icon: "✦", label: "Voice", detail: "Hazel - soft"),
                SettingsRowData(icon: "🔔", label: "When to interrupt", detail: "Approvals only"),
                SettingsRowData(icon: "🌙", label: "Quiet hours", detail: "10 PM - 7 AM")
            ])
            ClawdiaSettingsSection(title: "Areas", rows: [
                SettingsRowData(icon: "◇", label: "Manage areas", detail: "6 active", action: onOpenAreas),
                SettingsRowData(icon: "🔗", label: "Connected apps", detail: "3 of 5"),
                SettingsRowData(icon: "⚶", label: "Memory & context", detail: "On")
            ])
            ClawdiaSettingsSection(title: "Notifications", rows: [
                SettingsRowData(icon: "📣", label: "Push notifications", detail: "On", accessory: .toggle),
                SettingsRowData(icon: "🖇", label: "Daily digest", detail: "8:00 AM"),
                SettingsRowData(icon: "⏱", label: "Smart batching", detail: "On", accessory: .toggle)
            ])
            ClawdiaSettingsSection(title: "Privacy", rows: [
                SettingsRowData(icon: "🔒", label: "On-device first", detail: "Always"),
                SettingsRowData(icon: "↻", label: "What Clawdia remembers"),
                SettingsRowData(icon: "👁", label: "Audit log", detail: "Last 90 days"),
                SettingsRowData(icon: "↓", label: "Export your data")
            ])
            ClawdiaSettingsSection(title: "Account", rows: [
                SettingsRowData(icon: "💳", label: "Subscription", detail: "Plus"),
                SettingsRowData(icon: "↗", label: "Help & feedback"),
                SettingsRowData(icon: "→", label: "Sign out")
            ])
            ClawdiaSettingsSection(title: "Development", rows: [
                SettingsRowData(icon: "▣", label: "Component gallery", detail: "Tokens and controls", action: { onOpenDevelopment(.designSystem) }),
                SettingsRowData(icon: "✓", label: "Approvals and diffs", detail: "Bottom sheets", action: { onOpenDevelopment(.approvals) }),
                SettingsRowData(icon: "{}", label: "Code review cards", detail: "Email and diff states", action: { onOpenDevelopment(.approvals) }),
                SettingsRowData(icon: "⚶", label: "Memory graph", detail: "Tap and inspect", action: { onOpenDevelopment(.memory) })
            ])
            Text("Clawdia 1.4.2 - made with care")
                .font(ClawdiaType.caption)
                .foregroundStyle(ClawdiaColor.palette(theme).text3)
                .frame(maxWidth: .infinity)
                .padding(.vertical, ClawdiaSpacing.md)
        }
    }
}

private struct ThemeModeCard: View {
    @Environment(\.clawdiaTheme) private var currentTheme
    @Binding var theme: ClawdiaTheme

    var body: some View {
        let palette = ClawdiaColor.palette(currentTheme)
        ClawdiaCard {
            HStack {
                Label("Appearance", systemImage: "circle.lefthalf.filled")
                    .font(ClawdiaType.body.weight(.semibold))
                Spacer()
                Picker("Appearance", selection: $theme) {
                    ForEach(ClawdiaTheme.allCases, id: \.self) { theme in
                        Text(theme.rawValue.capitalized).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 150)
            }
            .foregroundStyle(palette.text)
        }
    }
}

private struct ProfileCard: View {
    var body: some View {
        ClawdiaCard {
            HStack {
                ClawdiaAvatar(size: 56, label: "S")
                VStack(alignment: .leading) {
                    Text("Saurav Atwell")
                        .font(ClawdiaType.subhead)
                    Text("Plus - since Jan 2026")
                        .font(ClawdiaType.caption)
                }
                Spacer()
                Image(systemName: "chevron.right")
            }
        }
    }
}

private struct SettingsSection: View {
    let title: String
    let rows: [String]

    var body: some View {
        ClawdiaSection(title) {
            VStack(spacing: 0) {
                ForEach(rows, id: \.self) { row in
                    HStack {
                        Text(row)
                            .font(ClawdiaType.body)
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .padding(ClawdiaSpacing.sm)
                    Divider()
                }
            }
        }
    }
}

private struct DevelopmentSettingsSection: View {
    let onOpenDevelopment: (DevScreen) -> Void

    var body: some View {
        ClawdiaSection("Development") {
            VStack(spacing: 0) {
                DevelopmentRow(title: "Component gallery", detail: "Tokens, type, cards, controls", screen: .designSystem, onOpenDevelopment: onOpenDevelopment)
                Divider()
                DevelopmentRow(title: "Approvals and diffs", detail: "Review every action card", screen: .approvals, onOpenDevelopment: onOpenDevelopment)
                Divider()
                DevelopmentRow(title: "Memory graph", detail: "Graph interaction sandbox", screen: .memory, onOpenDevelopment: onOpenDevelopment)
                Divider()
                DevelopmentRow(title: "Voice mode", detail: "Transcript and controls", screen: .voice, onOpenDevelopment: onOpenDevelopment)
            }
        }
    }
}

private struct DevelopmentRow: View {
    @Environment(\.clawdiaTheme) private var theme
    let title: String
    let detail: String
    let screen: DevScreen
    let onOpenDevelopment: (DevScreen) -> Void

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        Button {
            onOpenDevelopment(screen)
        } label: {
            HStack(spacing: ClawdiaSpacing.sm) {
                Image(systemName: "hammer")
                    .frame(width: 32, height: 32)
                    .background(palette.surface2)
                    .clipShape(RoundedRectangle(cornerRadius: ClawdiaRadius.sm, style: .continuous))
                VStack(alignment: .leading, spacing: ClawdiaSpacing.xxs) {
                    Text(title)
                        .font(ClawdiaType.body)
                    Text(detail)
                        .font(ClawdiaType.caption)
                        .foregroundStyle(palette.text2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(palette.text3)
            }
            .padding(ClawdiaSpacing.sm)
            .background(palette.surface)
        }
        .buttonStyle(.plain)
    }
}

public struct ConnectedAppsScreen: View {
    public init() {}

    public var body: some View {
        AppScroll {
            Text("connected apps")
                .font(ClawdiaType.display())
            SettingsSection(title: "Linked", rows: ["Mail - saurav@hey.com", "Calendar - 3 calendars", "Drive - Personal + Work"])
            SettingsSection(title: "Available", rows: ["Slack - Connect", "Notion - Connect", "Linear - Connect"])
        }
    }
}

public struct MemoryGraphScreen: View {
    @Environment(\.clawdiaTheme) private var theme
    @State private var selectedArea: LifeArea?

    public init() {}

    public var body: some View {
        let palette = ClawdiaColor.palette(theme)
        ZStack {
            palette.surface2.ignoresSafeArea()
            DotGrid()
                .foregroundStyle(palette.border2)
                .ignoresSafeArea()
            MemoryEdges()
                .stroke(palette.accent.opacity(0.45), lineWidth: 1.4)
                .frame(width: 320, height: 520)
            VStack {
                Text("memory")
                    .font(ClawdiaType.display())
                    .foregroundStyle(palette.text)
                Text("tap an area to inspect what Clawdia remembers")
                    .font(ClawdiaType.caption)
                    .foregroundStyle(palette.text2)
                Spacer()
            }
            .padding(ClawdiaSpacing.lg)
            ForEach(Array(LifeArea.allCases.enumerated()), id: \.element) { index, area in
                MemoryNode(area: area, index: index, selected: selectedArea == area) {
                    selectedArea = area
                }
            }
            ClawdiaAvatar(size: 78, label: "YOU")
            if let selectedArea {
                MemorySheet(area: selectedArea) {
                    self.selectedArea = nil
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: selectedArea)
        .clawdiaScreenBackground()
    }
}

private struct MemoryNode: View {
    @Environment(\.clawdiaTheme) private var theme
    let area: LifeArea
    let index: Int
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        let angle = Double(index) * 60
        Button(action: onTap) {
            VStack(spacing: ClawdiaSpacing.xs) {
                Image(systemName: area.icon)
                    .font(ClawdiaType.subhead)
                    .frame(width: selected ? 68 : 60, height: selected ? 68 : 60)
                    .background(selected ? palette.accentSoft : palette.surface)
                    .foregroundStyle(selected ? palette.accent2 : palette.text)
                    .clipShape(RoundedRectangle(cornerRadius: ClawdiaRadius.lg, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: ClawdiaRadius.lg, style: .continuous)
                            .stroke(selected ? palette.accent : palette.border, lineWidth: selected ? 1.5 : 0.5)
                    }
                Text(area.title)
                    .font(ClawdiaType.label)
                    .foregroundStyle(palette.text2)
            }
        }
        .buttonStyle(.plain)
        .offset(x: CGFloat(cos(angle * .pi / 180)) * 130, y: CGFloat(sin(angle * .pi / 180)) * 180)
    }
}

private struct DotGrid: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 16
            var x: CGFloat = 0
            while x < size.width {
                var y: CGFloat = 0
                while y < size.height {
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.4, height: 1.4)), with: .color(.primary.opacity(0.35)))
                    y += spacing
                }
                x += spacing
            }
        }
    }
}

private struct MemoryEdges: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        for index in 0..<LifeArea.allCases.count {
            let angle = Double(index) * 60
            let point = CGPoint(
                x: center.x + CGFloat(cos(angle * .pi / 180)) * 130,
                y: center.y + CGFloat(sin(angle * .pi / 180)) * 180
            )
            path.move(to: center)
            path.addLine(to: point)
        }
        return path
    }
}

private struct MemorySheet: View {
    @Environment(\.clawdiaTheme) private var theme
    let area: LifeArea
    let onClose: () -> Void

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        VStack(alignment: .leading, spacing: ClawdiaSpacing.sm) {
            HStack {
                Image(systemName: area.icon)
                    .frame(width: 40, height: 40)
                    .background(palette.accentSoft)
                    .foregroundStyle(palette.accent2)
                    .clipShape(RoundedRectangle(cornerRadius: ClawdiaRadius.md, style: .continuous))
                VStack(alignment: .leading) {
                    Text(area.title.lowercased())
                        .font(ClawdiaType.display(26))
                    Text("Pinned memories")
                        .font(ClawdiaType.caption)
                        .foregroundStyle(palette.text2)
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .frame(width: 30, height: 30)
                        .background(palette.surface2)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            ForEach(memoryNotes(for: area), id: \.self) { note in
                Label(note, systemImage: "checkmark.circle.fill")
                    .font(ClawdiaType.caption)
                    .foregroundStyle(palette.text)
            }
        }
        .padding(ClawdiaSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: ClawdiaRadius.xl, style: .continuous))
        .padding(ClawdiaSpacing.md)
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    private func memoryNotes(for area: LifeArea) -> [String] {
        switch area {
        case .personal: ["Mia's birthday is May 11", "Mom prefers evening calls", "Warm drafts land best"]
        case .work: ["Marcus likes direct PR summaries", "Q4 planning deck is active", "Acme deal is pinned"]
        case .money: ["Lisbon target is $1,840", "Dining out is above average", "Travel savings is active"]
        case .health: ["Run three times weekly", "Refill prescriptions before travel", "Dr. Park follow-up"]
        case .home: ["Plumber estimate pending", "Groceries due Friday", "Wi-Fi renewal in June"]
        case .travel: ["Lisbon flight watch", "Passport check needed", "Alfama stay preferred"]
        }
    }
}

public struct ContextNotesScreen: View {
    public init() {}

    public var body: some View {
        AppScroll {
            Text("context notes")
                .font(ClawdiaType.display())
            ForEach(["Mia prefers handwritten cards", "Marcus likes direct PR updates", "Lisbon budget target is $1,840"], id: \.self) { note in
                RichDataCard(title: "Pinned memory", systemImage: "note.text") {
                    Text(note)
                        .font(ClawdiaType.body)
                }
            }
        }
    }
}

public struct ContextBoardScreen: View {
    public init() {}

    public var body: some View {
        AppScroll {
            Text("context board")
                .font(ClawdiaType.display())
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: ClawdiaSpacing.xs) {
                ForEach(["People", "Places", "Tasks", "Documents"], id: \.self) { title in
                    RichDataCard(title: title, systemImage: "square.grid.2x2") {
                        Text("Drag-ready board tile for dev mode.")
                            .font(ClawdiaType.caption)
                    }
                }
            }
        }
    }
}

public struct DesignSystemGallery: View {
    public init() {}

    public var body: some View {
        AppScroll {
            ClawdiaWordmark()
            Text("color")
                .font(ClawdiaType.display())
            TokenSwatches()
            Text("type")
                .font(ClawdiaType.display())
            TypeRows()
            Text("components")
                .font(ClawdiaType.display())
            ClawdiaPrimaryButton("Primary action", systemImage: "checkmark") {}
            ClawdiaPillButton("Soft action", kind: .soft)
            ClawdiaCard {
                Text("Reusable card")
                    .font(ClawdiaType.body)
            }
        }
    }
}

private struct TokenSwatches: View {
    @Environment(\.clawdiaTheme) private var theme

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: ClawdiaSpacing.xs) {
            Swatch("Accent", palette.accent)
            Swatch("Ink", palette.text)
            Swatch("Paper", palette.background)
            Swatch("Surface", palette.surface)
            Swatch("Success", palette.success)
            Swatch("Warn", palette.warn)
            Swatch("Danger", palette.danger)
            Swatch("Border", palette.border)
        }
    }
}

private struct Swatch: View {
    let name: String
    let color: Color

    init(_ name: String, _ color: Color) {
        self.name = name
        self.color = color
    }

    var body: some View {
        VStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: ClawdiaRadius.md, style: .continuous)
                .fill(color)
                .frame(height: 70)
            Text(name)
                .font(ClawdiaType.caption)
        }
    }
}

private struct TypeRows: View {
    var body: some View {
        VStack(alignment: .leading, spacing: ClawdiaSpacing.md) {
            Text("good morning, friend").font(ClawdiaType.display(42))
            Text("What's on for today?").font(ClawdiaType.title)
            Text("Three things you asked me to handle").font(ClawdiaType.subhead)
            Text("I drafted a reply and queued it for review.").font(ClawdiaType.body)
            Text("04:25 PM - delivered").font(ClawdiaType.caption)
            Text("renderUserCard(props)").font(ClawdiaType.mono)
        }
    }
}

private struct StatusPill: View {
    @Environment(\.clawdiaTheme) private var theme
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        Label(title, systemImage: systemImage)
            .font(ClawdiaType.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(palette.accentSoft)
            .foregroundStyle(palette.accent2)
            .clipShape(Capsule())
    }
}

struct AppScroll<Content: View>: View {
    @Environment(\.clawdiaTheme) private var theme
    let keyboardDismissMode: ScrollDismissesKeyboardMode
    let bottomPadding: CGFloat
    let content: Content

    init(
        keyboardDismissMode: ScrollDismissesKeyboardMode = .automatic,
        bottomPadding: CGFloat = 92,
        @ViewBuilder content: () -> Content
    ) {
        self.keyboardDismissMode = keyboardDismissMode
        self.bottomPadding = bottomPadding
        self.content = content()
    }

    var body: some View {
        let palette = ClawdiaColor.palette(theme)
        ScrollView {
            VStack(alignment: .leading, spacing: ClawdiaSpacing.lg) {
                content
            }
            .padding(ClawdiaSpacing.lg)
            .padding(.bottom, bottomPadding)
            .frame(maxWidth: 520, alignment: .topLeading)
            .frame(maxWidth: .infinity)
        }
        .background(palette.background)
        .scrollDismissesKeyboard(keyboardDismissMode)
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 320
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
