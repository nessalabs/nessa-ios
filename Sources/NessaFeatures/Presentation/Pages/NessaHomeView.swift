import NessaDesignSystem
import SwiftUI

/// What the home composer hands to the chat it starts, which shows it and sends it.
struct HomeFirstMessage {
  let text: String
  let attachments: [DraftAttachment]
}

/// The screen the app opens on: a greeting and a composer. Sending starts a new chat with
/// that message; the sidebar holds every chat there already is.
struct NessaHomeView: View {
  @ObservedObject var store: MessagesViewModel
  @ObservedObject var desktop: DesktopLinkViewModel
  @ObservedObject var dictation: DictationViewModel
  let onMenu: () -> Void
  let onPair: () -> Void
  let onCompose: () -> Void
  /// Starts a chat with the composer's message; the caller opens it at once.
  let onStart: (HomeFirstMessage) -> Void
  @State private var draft = ""
  @State private var reply: MessageReply?
  @State private var attachments: [DraftAttachment] = []
  @State private var now = Date()
  /// Reconnecting has run long enough that the pill offers Try again.
  @State private var reconnectSlow = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(spacing: MessagesStyle.greetingGap) {
      Spacer(minLength: 0)
      Text(HomeGreeting.text(at: now))
        .font(MessagesStyle.greeting).foregroundStyle(MessagesStyle.foreground)
        .multilineTextAlignment(.center)
        .accessibilityAddTraits(.isHeader)
      if needsPairing {
        // Nothing to talk to yet: pairing with the Mac is the way in.
        VStack(spacing: NessaSpacing.sm) {
          Text("Pair with your Mac to start chatting.")
            .font(MessagesStyle.greetingDetail).foregroundStyle(MessagesStyle.secondary)
          Button("Pair with your Mac", action: onPair).buttonStyle(.nessaPrimary)
        }
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, MessagesStyle.horizontal)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .contentShape(Rectangle())
    .nessaTapDismissesKeyboard()
    // Back on home from a chat, no field here holds the keyboard: one left up by the chat
    // would float over the greeting with nothing to type into.
    .onAppear { NessaKeyboard.dismiss() }
    .background { NessaHomeLight() }
    .safeAreaInset(edge: .top, spacing: 0) { topBar }
    .messagesBar(edge: .bottom) {
      VStack(spacing: NessaSpacing.xs) {
        if waitingForLink {
          reconnectPill
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        if !needsPairing {
          MessageComposer(
            draft: $draft, reply: $reply, attachments: $attachments,
            recipient: recipient, dictation: dictation,
            sending: store.busy, connected: store.connected,
            attachmentPolicy: store.attachmentPolicy,
            submissionAllowed: canStart,
            placeholder: "Message \(recipient) or hold to talk",
            endsEditingOnSend: true,
            onSend: start)
        }
      }
      .padding(.bottom, MessagesStyle.bottomInset)
      .animation(reduceMotion ? nil : NessaMotion.enter, value: waitingForLink)
      // The light rises behind the composer, not through it: a dark ground under the bar
      // keeps its text clear, and the glow shows above.
      .background {
        LinearGradient(
          stops: [
            .init(color: MessagesStyle.background, location: 0),
            .init(color: MessagesStyle.background.opacity(0.85), location: 0.55),
            .init(color: MessagesStyle.background.opacity(0), location: 1),
          ], startPoint: .bottom, endPoint: .top
        )
        .padding(.top, -MessagesStyle.footerRise)
        .ignoresSafeArea(edges: .bottom)
      }
    }
    #if os(iOS)
      .toolbar(.hidden, for: .navigationBar)
    #endif
    // Try again appears only once a reconnect has run past a few seconds; a quick one shows
    // the pill working and then just goes.
    .task(id: waitingForLink) {
      reconnectSlow = false
      guard waitingForLink else { return }
      try? await Task.sleep(for: .seconds(MessagesStyle.reconnectPatience))
      if !Task.isCancelled, waitingForLink { reconnectSlow = true }
    }
    // The greeting follows the clock while the app stays open across an hour.
    .task {
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(60))
        now = Date()
      }
    }
  }

  private var topBar: some View {
    HStack {
      Button(action: onMenu) {
        NessaIcon(.menu)
          .frame(width: MessagesStyle.homeButton, height: MessagesStyle.homeButton)
          // The whole disc takes the tap, not only the icon's thin strokes.
          .contentShape(Circle())
          .messagesGlass()
      }
      .buttonStyle(.nessaPress)
      .accessibilityLabel("Open sidebar")
      Spacer()
      Button(action: onCompose) {
        NessaIcon(.compose)
          .frame(width: MessagesStyle.homeButton, height: MessagesStyle.homeButton)
          // The whole disc takes the tap, not only the icon's thin strokes.
          .contentShape(Circle())
          .messagesGlass()
      }
      .buttonStyle(.nessaPress)
      .disabled(!canStart)
      .accessibilityLabel("New chat")
    }
    .foregroundStyle(MessagesStyle.foreground)
    .padding(.horizontal, NessaSpacing.md)
    .padding(.top, NessaSpacing.xs)
  }

  /// Who a new chat talks to: the gateway's one agent when it has one, else Nessa, which
  /// picks the agent itself.
  private var recipient: String {
    store.agentProfiles.count == 1 ? store.agentProfiles[0].displayName : "Nessa"
  }

  /// Not connected, not on the way back, and no Mac to connect to.
  private var needsPairing: Bool {
    !store.connected && !store.reconnecting && desktop.linked == nil
  }

  /// "Reconnecting…" while the link comes back; once it has run long, Try again.
  private var reconnectPill: MessagesStatusPill {
    guard reconnectSlow else { return MessagesStatusPill("Reconnecting…", working: true) }
    let store = store
    let retry: () -> Void = { Task { await store.reconnectLinked() } }
    return MessagesStatusPill(
      "Can't reach your Mac", working: false, action: (title: "Try again", perform: retry))
  }

  private var waitingForLink: Bool {
    !store.connected && (store.reconnecting || desktop.linked != nil)
  }

  /// The same conditions the gateway puts on making a chat.
  private var canStart: Bool { store.canCreateChat }

  /// The draft moves to the new chat, which opens at once and shows whether it got through.
  private func start() {
    let first = HomeFirstMessage(text: draft, attachments: attachments)
    draft = ""
    attachments = []
    onStart(first)
  }
}
