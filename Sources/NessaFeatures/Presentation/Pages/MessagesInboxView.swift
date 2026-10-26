import NessaDesignSystem
import SwiftUI

struct MessagesInboxView: View {
  @ObservedObject var store: MessagesViewModel
  /// The Mac this phone is paired with. Its chats come through the session;
  /// the inbox only asks whether there is one, to offer pairing when not.
  @ObservedObject var desktop: DesktopLinkViewModel
  let onPair: () -> Void
  let onSettings: () -> Void
  let onOpen: (String) -> Void
  let onCompose: () -> Void
  let onOpenComposer: (String) -> Void
  @State private var editing = false
  @State private var showingArchived = false
  @State private var selected: Set<String> = []
  /// A Delete or Archive waiting on the system's alert.
  @State private var asking: ChatsConfirmation?
  @State private var deleting = false
  /// Rows are fading out or the list is closing up after them.
  @State private var removing = false
  /// Chats being deleted or archived. Their rows first fade out where they stand (`fading`),
  /// then leave the list and the pinned grid on the layout spring (`leaving`), so the rows
  /// below close the gap through empty space rather than through fading text. The store's
  /// own change lands later, outside any animation, once there is nothing left to see go.
  @State private var fading: Set<String> = []
  @State private var leaving: Set<String> = []
  @State private var search = ""
  @State private var pinRefusals = 0
  /// Reconnecting has taken long enough that the pill offers Try again.
  @State private var reconnectSlow = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    List {
      Group {
        // Phone sync belongs to a gateway address; a paired Mac's link speaks in the pill.
        if let status = store.phoneSyncError, desktop.linked == nil {
          Button(status, action: onSettings).font(MessagesStyle.caption)
            .foregroundStyle(MessagesStyle.secondary).padding(.vertical, NessaSpacing.md)
        }
        if store.pendingLoadError != nil { PendingDeliveryUnavailable(store: store) }
        ForEach(store.pendingCreations, id: \.requestID) { command in
          PendingCommandActions(command: command, store: store, onCreated: onOpen)
        }
        if !pinnedShown.isEmpty {
          PinnedChatsGrid(
            store: store, onOpen: onOpen, onOpenComposer: onOpenComposer,
            onArchive: { ask([$0], .archive) }, onDelete: { ask([$0], .delete) },
            enabled: !deleting, leaving: leaving)
        }
        // While the link comes back the list keeps what it last showed; the pill at the
        // bottom says what is happening.
        if !store.connected, !store.reconnecting, desktop.linked == nil {
          // Nothing to show yet: pairing with the Mac is the way in.
          VStack(spacing: NessaSpacing.sm) {
            Text("Pair with your Mac to see your chats here.")
              .font(MessagesStyle.body).foregroundStyle(MessagesStyle.secondary)
              .multilineTextAlignment(.center)
            Button("Pair with your Mac", action: onPair).buttonStyle(.nessaPrimary)
          }
          .frame(maxWidth: .infinity).padding(NessaSpacing.xl)
        } else if !store.connected {
          EmptyView()
        } else if store.visibleConversations.isEmpty {
          InboxEmptyState(onCompose: onCompose)
            .disabled(
              !store.conversationAuthorityReady || store.pendingLoadError != nil
                || !store.pendingCreations.isEmpty)
        } else if showingArchived && filtered.isEmpty {
          Text("No archived chats.").font(MessagesStyle.body)
            .foregroundStyle(MessagesStyle.secondary).padding(.vertical, NessaSpacing.xl)
        }
        ForEach(filtered) { conversation in
          Button {
            if editing {
              // Animated, so the action bar rises with the first pick and sinks with the last.
              withAnimation(reduceMotion ? nil : NessaMotion.enter) {
                if !selected.insert(conversation.id).inserted { selected.remove(conversation.id) }
              }
            } else {
              onOpen(conversation.id)
            }
          } label: {
            HStack(spacing: NessaSpacing.sm) {
              if editing {
                NessaSelectionMark(selected: selected.contains(conversation.id))
                  .transition(.move(edge: .leading).combined(with: .opacity))
              }
              ConversationRow(
                conversation: conversation, agentName: store.agentName(for: conversation.id))
            }
            .background {
              RoundedRectangle(cornerRadius: MessagesStyle.selectedRowRadius, style: .continuous)
                .fill(
                  editing && selected.contains(conversation.id)
                    ? MessagesStyle.selectedRowFill : .clear
                )
                .padding(.horizontal, -NessaSpacing.xs)
                .animation(reduceMotion ? nil : NessaMotion.standard(), value: selected)
            }
            .contentShape(Rectangle())
            .opacity(fading.contains(conversation.id) ? 0 : 1)
            // A row leaving (pinned, archived, deleted) collapses inside its own bounds, so
            // its text never slides over the row moving up into its place. The mask is
            // widened sideways only, to keep the selected fill's overhang.
            .mask { Rectangle().padding(.horizontal, -NessaSpacing.xs) }
          }.buttonStyle(.plain)
            // Rows wait out a deletion without dimming: the list stays as it looks.
            .allowsHitTesting(!deleting)
            .accessibilityLabel(
              editing
                ? "Select \(store.chatName(conversation.id))" : store.chatName(conversation.id)
            )
            .accessibilityAddTraits(selected.contains(conversation.id) ? .isSelected : [])
            .chatContextMenu(
              store: store, identifier: conversation.id,
              // Off while rows leave, as it already is while selecting or deleting, where the
              // close runs smoothly; with it on, a single archive's close jumped.
              enabled: !editing && !deleting && !removing,
              onTap: { onOpen(conversation.id) },
              onCommit: onOpenComposer,
              onArchive: { ask([$0], .archive) },
              onDelete: { ask([$0], .delete) }
            )
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
              if !editing && !showingArchived {
                // A swipe action's button looks the same disabled or not, so a full pin row
                // says so in its label and colour, and a tap on it buzzes instead of silently
                // doing nothing.
                let canPin = store.canTogglePin(conversation.id)
                Button(
                  store.isPinned(conversation.id) ? "Unpin" : canPin ? "Pin" : "Pins full",
                  systemImage: store.isPinned(conversation.id) ? "pin.slash.fill" : "pin.fill"
                ) {
                  if canPin {
                    changeLayout { store.togglePin(conversation.id) }
                  } else {
                    pinRefusals += 1
                  }
                }.tint(canPin ? MessagesStyle.pinAction : MessagesStyle.control)
              }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
              if !editing {
                // Each asks first; nothing goes on one tap.
                Button {
                  ask([conversation.id], .delete)
                } label: {
                  Label("Delete", systemImage: "trash")
                }.tint(MessagesStyle.danger).disabled(
                  !store.connected || !store.conversationAuthorityReady)
                Button(showingArchived ? "Unarchive" : "Archive", systemImage: "archivebox") {
                  ask([conversation.id], .archive)
                }.tint(MessagesStyle.archiveAction)
              }
            }
        }
        if !store.listComplete {
          Text("Some conversations could not be listed.").font(MessagesStyle.caption)
            .foregroundStyle(MessagesStyle.secondary)
        }
      }.listRowInsets(
        EdgeInsets(
          top: 0, leading: MessagesStyle.horizontal, bottom: 0, trailing: MessagesStyle.horizontal)
      )
      .listRowSeparator(.hidden).listRowBackground(Color.clear)
    }.listStyle(.plain).scrollContentBackground(.hidden)
      // An alert, centred with its own Cancel: a confirmation dialog on iOS 26 is a popover
      // anchored to the list, pointing at none of the rows or buttons that asked.
      .alert(
        asking?.title(archived: showingArchived) ?? "", isPresented: askingShown,
        presenting: asking
      ) { ask in
        Button(
          ask.verb(archived: showingArchived), role: ask.action == .delete ? .destructive : nil
        ) { perform(ask) }.disabled(
          ask.action == .delete && (!store.connected || !store.conversationAuthorityReady))
        Button("Cancel", role: .cancel) {}
      } message: { ask in
        if ask.action == .delete { Text("This can't be undone.") }
      }
      .environment(\.defaultMinListRowHeight, 0)
      .sensoryFeedback(.impact(flexibility: .soft), trigger: store.pinnedChats)
      .sensoryFeedback(.warning, trigger: pinRefusals)
      .messagesAmbientGround()
      .messagesScrollEdges()
      .scrollDismissesKeyboard(.interactively)
      .messagesFooterGrain()
      // The system bar, as in the thread, with the same grain over its edge.
      .messagesTopGrain()
      .nessaInlineNavigationTitle()
      .toolbar {
        InboxToolbar(
          editing: editing,
          onEdit: {
            // The marks slide in from the edge as the rows make room, on one spring.
            withAnimation(reduceMotion ? nil : NessaMotion.enter) {
              editing.toggle()
              selected = []
            }
          }, showingArchived: showingArchived,
          onToggleArchived: {
            showingArchived.toggle()
            selected = []
            // The gateway holds which chats are archived; read them each time they are shown.
            if showingArchived { Task { await store.loadArchived() } }
          }, disabled: deleting
        )
      }
      .messagesBar(edge: .bottom) {
        if editing {
          // Only while something is selected; it goes with what it acted on.
          if !selected.isEmpty {
            SelectionActions(
              showingArchived: showingArchived, archiveEnabled: !deleting,
              deleteEnabled: !deleting && store.connected && store.conversationAuthorityReady,
              onArchive: { ask(selected, .archive) }, onDelete: { ask(selected, .delete) }
            )
            .padding(.horizontal, MessagesStyle.horizontal)
            .padding(.bottom, MessagesStyle.bottomInset)
            .transition(.move(edge: .bottom).combined(with: .opacity))
          }
        } else {
          VStack(spacing: NessaSpacing.xs) {
          if waitingForLink {
            reconnectPill.transition(.move(edge: .bottom).combined(with: .opacity))
          }
          HStack(spacing: MessagesStyle.toolbarGap) {
            NessaSearchField(text: $search)
            Button(action: onCompose) {
              Group {
                if store.busy {
                  ProgressView()
                } else {
                  Image(systemName: "square.and.pencil").font(MessagesStyle.icon)
                }
              }
              .frame(width: MessagesStyle.composerHeight, height: MessagesStyle.composerHeight)
              .messagesGlass()
            }.buttonStyle(.nessaPress).disabled(!store.canCreateChat)
            .accessibilityLabel(store.busy ? "Creating chat" : "New message")
          }
          }.padding(.horizontal, MessagesStyle.horizontal).padding(
            .bottom, MessagesStyle.bottomInset)
          .animation(reduceMotion ? nil : NessaMotion.enter, value: waitingForLink)
        }
      }
      // Try again appears only once a reconnect has run past a few seconds; a quick one
      // shows the pill working and then just goes.
      .task(id: waitingForLink && !store.busy) {
        reconnectSlow = false
        guard waitingForLink else { return }
        try? await Task.sleep(for: .seconds(MessagesStyle.reconnectPatience))
        if !Task.isCancelled, waitingForLink { reconnectSlow = true }
      }
      .onChange(of: store.connected) { _, _ in
        selected = []
        editing = false
        asking = nil
      }
      .refreshable {
        if !store.connected, store.linkedDesktopID != nil {
          await store.reconnectLinked()
          return
        }
        guard store.connected || desktop.linked == nil else { return }
        if showingArchived {
          await store.loadArchived()
          return
        }
        do { try await store.refreshList() } catch { store.error = error.localizedDescription }
      }
  }
  /// "Reconnecting…" while the link comes back; once it has run long, Try again.
  private var reconnectPill: MessagesStatusPill {
    guard reconnectSlow else { return MessagesStatusPill("Reconnecting…", working: true) }
    let store = store
    let retry: () -> Void = { Task { await store.reconnectLinked() } }
    return MessagesStatusPill(
      "Can't reach your Mac", working: false, action: (title: "Try again", perform: retry))
  }
  /// Paired with a Mac, or bringing a saved connection back, and not connected yet.
  private var waitingForLink: Bool {
    !store.connected && (store.reconnecting || desktop.linked != nil)
  }
  private var askingShown: Binding<Bool> {
    Binding(get: { asking != nil }, set: { if !$0 { asking = nil } })
  }
  private func ask(_ ids: Set<String>, _ action: ChatsConfirmation.Action) {
    // Asked on the next turn of the run loop, after the swipe or menu that asked has begun
    // closing: presented in the same update, the alert could be dropped.
    Task { asking = ChatsConfirmation(ids: ids, action: action) }
  }
  private func perform(_ ask: ChatsConfirmation) {
    // The bar sinks as its selection goes, with the rows it acted on.
    withAnimation(reduceMotion ? nil : NessaMotion.enter) {
      selected.subtract(ask.ids)
    }
    switch ask.action {
    case .delete: delete(ask.ids)
    case .archive: archive(ask.ids, archived: !showingArchived)
    }
  }
  private func delete(_ ids: Set<String>) {
    deleting = true
    fadeOut(ids) {
      // The store hides a chat the moment its deletion starts, so the rows leave first.
      changeLayout { leaving.formUnion(ids) }
      await store.deleteConversations(ids)
      selected.formIntersection(Set(store.conversations.map(\.id)))
      deleting = false
      // A chat the gateway kept comes back on the same spring.
      changeLayout {
        leaving.subtract(ids)
        fading.subtract(ids)
      }
    }
  }
  private func archive(_ ids: Set<String>, archived: Bool) {
    fadeOut(ids) {
      // The rows leave on the view's own state, as a deletion's do; the store moves them only
      // once the list has closed up, outside any animation, so its update can't jolt the
      // list mid-close.
      changeLayout { leaving.formUnion(ids) }
      try? await Task.sleep(for: .seconds(MessagesStyle.rowSettle))
      for id in ids { await store.setArchived(archived, conversationID: id) }
      leaving.subtract(ids)
      fading.subtract(ids)
    }
  }
  /// Fades the rows out where they stand, then runs what takes them away. Timed rather than
  /// waiting on the fade's completion, which can fire at once when the list redraws the rows
  /// in the same update (the selection clearing and the bar sinking).
  private func fadeOut(_ ids: Set<String>, then remove: @escaping @MainActor () async -> Void) {
    removing = true
    withAnimation(reduceMotion ? nil : NessaMotion.standard(MessagesStyle.rowFadeOut)) {
      fading.formUnion(ids)
    }
    Task {
      if !reduceMotion { try? await Task.sleep(for: .seconds(MessagesStyle.rowFadeOut)) }
      await remove()
      removing = false
    }
  }
  /// The pinned chats the grid shows right now, or none while it is hidden.
  private var pinnedShown: [String] {
    guard !editing && !showingArchived && search.isEmpty else { return [] }
    return store.pinnedChats.filter { !store.isDeleting($0) && !leaving.contains($0) }
  }
  /// Moves the list and the pinned grid on one spring, from the change itself. The list
  /// carries no implicit animation of its own: an `.animation` on a List mixes SwiftUI's
  /// animation into the collection view's own row updates, and a row inserted while the grid
  /// resizes could be left drawn over its neighbour.
  private func changeLayout(_ change: () -> Void) {
    withAnimation(reduceMotion ? nil : NessaMotion.enter, change)
  }
  private var filtered: [NessaConversation] {
    store.visibleConversations.filter {
      !leaving.contains($0.id) && (store.archivedChats.contains($0.id) == showingArchived)
        && (editing || showingArchived || !store.isPinned($0.id))
        && (search.isEmpty || ($0.title ?? "").localizedCaseInsensitiveContains(search)
          || ($0.preview ?? "").localizedCaseInsensitiveContains(search))
    }
  }
}

/// Chats waiting on the alert, and what will happen to them.
private struct ChatsConfirmation {
  enum Action { case delete, archive }
  let ids: Set<String>
  let action: Action
  func verb(archived: Bool) -> String {
    action == .delete ? "Delete" : archived ? "Unarchive" : "Archive"
  }
  func title(archived: Bool) -> String {
    let chats = ids.count == 1 ? "this chat" : "\(ids.count) chats"
    return "\(verb(archived: archived)) \(chats)?"
  }
}
