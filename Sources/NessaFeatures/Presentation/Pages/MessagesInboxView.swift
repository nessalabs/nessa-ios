import NessaDesignSystem
import SwiftUI

struct MessagesInboxView: View {
  @ObservedObject var store: MessagesViewModel
  let onSettings: () -> Void
  let onOpen: (String) -> Void
  let onCompose: () -> Void
  let onOpenComposer: (String) -> Void
  @State private var editing = false
  @State private var showingArchived = false
  @State private var selected: Set<String> = []
  /// Select mode was opened for one pinned chat's Delete or Archive (a disc has no row to
  /// confirm on), so it closes again after the slide.
  @State private var selectingOne = false
  /// A row's Delete or Archive waiting for its second tap, asked on the row itself.
  @State private var confirming: RowConfirmation?
  @State private var deleting = false
  /// Chats being deleted or archived. Their rows first fade out where they stand (`fading`),
  /// then leave the list on the layout spring, so the rows below close the gap through empty
  /// space rather than through fading text. Deleted chats also leave the pinned grid
  /// (`leaving`); the store's own removal lands later, outside any animation, once there is
  /// nothing left to see go.
  @State private var fading: Set<String> = []
  @State private var leaving: Set<String> = []
  @State private var search = ""
  @State private var pinRefusals = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  var body: some View {
    List {
      Group {
        if let status = store.phoneSyncError {
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
            onArchive: selectOne, onDelete: selectOne, enabled: !deleting, leaving: leaving)
        }
        if !store.connected {
          Button(store.reconnecting ? "Reconnecting…" : "Connect to Nessa", action: onSettings)
            .font(MessagesStyle.body).padding(NessaSpacing.xl)
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
            if confirming != nil {
              // A tap anywhere else lets a pending confirmation go.
              setConfirming(nil)
            } else if editing {
              // Animated, so the delete bar rises with the first pick and sinks with the last.
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
            .overlay(alignment: .trailing) {
              if let ask = confirming, ask.id == conversation.id {
                NessaInlineConfirm(
                  ask.title(archived: showingArchived), symbol: ask.symbol,
                  tint: ask.action == .delete ? MessagesStyle.danger : MessagesStyle.archiveAction
                ) { perform(ask) }
                .disabled(
                  ask.action == .delete
                    && (!store.connected || !store.conversationAuthorityReady))
              }
            }
            // Rows wait out a deletion without dimming: the list stays as it looks.
            .allowsHitTesting(!deleting)
            .accessibilityLabel(
              editing
                ? "Select \(store.chatName(conversation.id))" : store.chatName(conversation.id)
            )
            .accessibilityAddTraits(selected.contains(conversation.id) ? .isSelected : [])
            .chatContextMenu(
              store: store, identifier: conversation.id,
              enabled: !editing && !deleting,
              onTap: { onOpen(conversation.id) }, onCommit: onOpenComposer,
              onArchive: { setConfirming(.init(id: $0, action: .archive)) },
              onDelete: { setConfirming(.init(id: $0, action: .delete)) }
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
                // Each asks again on the row once the swipe closes; nothing goes on one tap.
                Button {
                  setConfirming(.init(id: conversation.id, action: .delete))
                } label: {
                  Label("Delete", systemImage: "trash")
                }.tint(MessagesStyle.danger).disabled(
                  !store.connected || !store.conversationAuthorityReady)
                Button(showingArchived ? "Unarchive" : "Archive", systemImage: "archivebox") {
                  setConfirming(.init(id: conversation.id, action: .archive))
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
      // A pinned chat's Delete or Archive backs out with a tap anywhere on the list.
      .overlay {
        if selectingOne && !deleting {
          Color.clear.contentShape(Rectangle())
            .onTapGesture { cancelSelectingOne() }
            .accessibilityAddTraits(.isButton).accessibilityLabel("Keep chat")
        }
      }
      // Scrolling lets a pending confirmation go, so it never sits on a row out of sight.
      .onScrollPhaseChange { _, phase in
        if phase == .interacting && confirming != nil { setConfirming(nil) }
      }
      .sensoryFeedback(.warning, trigger: confirming) { _, new in new != nil }
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
          editing: editing, cancelsDelete: selectingOne,
          accountSeed: store.currentGatewayAddress ?? "nessa",
          onEdit: {
            // The marks slide in from the edge as the rows make room, on one spring.
            withAnimation(reduceMotion ? nil : NessaMotion.enter) {
              editing.toggle()
              selected = []
              selectingOne = false
              confirming = nil
            }
          }, onSettings: onSettings, showingArchived: showingArchived,
          onToggleArchived: {
            showingArchived.toggle()
            selected = []
            confirming = nil
            // A pinned chat's Delete or Archive has nothing left to act on in the other list.
            if selectingOne {
              editing = false
              selectingOne = false
            }
          }, disabled: deleting
        )
      }
      .messagesBar(edge: .bottom) {
        if editing {
          // The bar is the slides themselves, so acting on a selection needs no sheet. They
          // are there only while something is selected, and go with what they acted on.
          if !selected.isEmpty {
            SelectionSlides(
              count: selected.count, showingArchived: showingArchived,
              archiveEnabled: !deleting,
              deleteEnabled: !deleting && store.connected && store.conversationAuthorityReady,
              onArchive: { archive(takeSelection(), archived: !showingArchived) },
              onDelete: { delete(takeSelection()) }
            )
            .padding(.horizontal, MessagesStyle.horizontal)
            .padding(.bottom, MessagesStyle.bottomInset)
            .transition(.move(edge: .bottom).combined(with: .opacity))
          }
        } else {
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
            }.buttonStyle(.nessaPress).disabled(
              !store.connected || !store.conversationAuthorityReady || store.busy
                || store.pendingLoadError != nil
                || !store.pendingCreations.isEmpty
            )
            .accessibilityLabel(store.busy ? "Creating chat" : "New message")
          }.padding(.horizontal, MessagesStyle.horizontal).padding(
            .bottom, MessagesStyle.bottomInset)
        }
      }
      .onChange(of: store.connected) { _, _ in
        selected = []
        editing = false
        selectingOne = false
        confirming = nil
      }
      .refreshable {
        do { try await store.refreshList() } catch { store.error = error.localizedDescription }
      }
  }
  /// Asks for (or, with nil, lets go of) a row's second tap.
  private func setConfirming(_ ask: RowConfirmation?) {
    withAnimation(reduceMotion ? nil : NessaMotion.morph) { confirming = ask }
  }
  private func perform(_ ask: RowConfirmation) {
    setConfirming(nil)
    switch ask.action {
    case .delete: delete([ask.id])
    case .archive: archive([ask.id], archived: !showingArchived)
    }
  }
  /// A pinned chat's Delete or Archive: its disc has no row to ask on, so select mode opens
  /// with just that chat picked, and the slides rise.
  private func selectOne(_ id: String) {
    withAnimation(reduceMotion ? nil : NessaMotion.enter) {
      selectingOne = !editing
      editing = true
      selected = [id]
    }
  }
  private func cancelSelectingOne() {
    withAnimation(reduceMotion ? nil : NessaMotion.enter) {
      editing = false
      selected = []
      selectingOne = false
    }
  }
  /// Hands over what is selected and clears it, so the slides sink with what they act on
  /// (and select mode closes if it opened for one chat).
  private func takeSelection() -> Set<String> {
    let ids = selected
    withAnimation(reduceMotion ? nil : NessaMotion.enter) {
      selected = []
      if selectingOne {
        editing = false
        selectingOne = false
      }
    }
    return ids
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
      changeLayout { for id in ids { store.setArchived(archived, conversationID: id) } }
      // Gone from this list now; once it has closed up, the rows may show again in the other.
      try? await Task.sleep(for: .seconds(MessagesStyle.rowSettle))
      fading.subtract(ids)
    }
  }
  /// Fades the rows out where they stand, then runs what takes them away. Timed rather than
  /// waiting on the fade's completion, which can fire at once when the list redraws the rows
  /// in the same update (the selection clearing and the slides sinking).
  private func fadeOut(_ ids: Set<String>, then remove: @escaping @MainActor () async -> Void) {
    withAnimation(reduceMotion ? nil : NessaMotion.standard(MessagesStyle.rowFadeOut)) {
      fading.formUnion(ids)
    }
    Task {
      if !reduceMotion { try? await Task.sleep(for: .seconds(MessagesStyle.rowFadeOut)) }
      await remove()
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

/// A row's one-tap action waiting for its second tap.
private struct RowConfirmation: Equatable {
  enum Action { case delete, archive }
  let id: String
  let action: Action
  var symbol: String { action == .delete ? "trash" : "archivebox" }
  func title(archived: Bool) -> String {
    action == .delete ? "Delete" : archived ? "Unarchive" : "Archive"
  }
}
