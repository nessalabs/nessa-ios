import NessaDesignSystem
import SwiftUI

/// What the home composer hands to the chat it starts, for that chat's own composer to send.
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
  /// A chat was made for the composer's message; the caller opens it and sends.
  let onStart: (_ conversationID: String, _ first: HomeFirstMessage) -> Void
  @State private var draft = ""
  @State private var reply: MessageReply?
  @State private var attachments: [DraftAttachment] = []
  @State private var starting = false
  @State private var now = Date()
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
    .background { NessaHomeLight() }
    .safeAreaInset(edge: .top, spacing: 0) { topBar }
    .messagesBar(edge: .bottom) {
      VStack(spacing: NessaSpacing.xs) {
        if waitingForLink {
          MessagesStatusPill("Reconnecting…", working: true)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        if !needsPairing {
          MessageComposer(
            draft: $draft, reply: $reply, attachments: $attachments,
            recipient: recipient, dictation: dictation,
            sending: starting || store.busy, connected: store.connected,
            attachmentPolicy: store.attachmentPolicy,
            submissionAllowed: canStart,
            placeholder: "Message \(recipient) or hold to talk",
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

  private var waitingForLink: Bool {
    !store.connected && (store.reconnecting || desktop.linked != nil)
  }

  /// The same conditions the gateway puts on making a chat.
  private var canStart: Bool {
    store.canCreateChat && !starting
  }

  private func start() {
    let first = HomeFirstMessage(text: draft, attachments: attachments)
    starting = true
    Task {
      defer { starting = false }
      guard let id = await store.create() else { return }
      // The draft moves to the new chat, which sends it; a chat that could not be made keeps
      // it here.
      draft = ""
      attachments = []
      onStart(id, first)
    }
  }
}
