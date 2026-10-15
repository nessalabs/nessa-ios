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
  /// Select mode was opened by a single chat's Delete, so it closes again after the delete.
  @State private var selectingToDelete = false
  @State private var deleting = false
  /// Chats being deleted. Their rows first fade out where they stand (`fading`), then leave
  /// the list and the pinned grid on the layout spring (`leaving`), so the rows below close
  /// the gap through empty space rather than through fading text. The store's own removal
  /// lands later, outside any animation, once there is nothing left to see go.
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
            onDelete: selectToDelete, enabled: !deleting, leaving: leaving)
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
            if editing {
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
              onDelete: selectToDelete
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
                Button {
                  selectToDelete(conversation.id)
                } label: {
                  Label("Delete", systemImage: "trash")
                }.tint(MessagesStyle.danger).disabled(
                  !store.connected || !store.conversationAuthorityReady)
                Button(showingArchived ? "Unarchive" : "Archive", systemImage: "archivebox") {
                  changeLayout {
                    store.setArchived(!showingArchived, conversationID: conversation.id)
                  }
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
      // A single chat's Delete backs out with a tap anywhere on the list, as the slide did
      // before it became the bar.
      .overlay {
        if selectingToDelete && !deleting {
          Color.clear.contentShape(Rectangle())
            .onTapGesture { cancelDelete() }
            .accessibilityAddTraits(.isButton).accessibilityLabel("Keep chat")
        }
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
          editing: editing, cancelsDelete: selectingToDelete,
          accountSeed: store.currentGatewayAddress ?? "nessa",
          onEdit: {
            // The marks slide in from the edge as the rows make room, on one spring.
            withAnimation(reduceMotion ? nil : NessaMotion.enter) {
              editing.toggle()
              selected = []
              selectingToDelete = false
            }
          }, onSettings: onSettings, showingArchived: showingArchived,
          onToggleArchived: {
            showingArchived.toggle()
            selected = []
          }, disabled: deleting
        )
      }
      .messagesBar(edge: .bottom) {
        if editing {
          // The bar is the slide itself, so deleting a selection needs no sheet. It is there
          // only while something is selected, and goes with what it deleted.
          if !selected.isEmpty {
            NessaSlideToConfirm(
              "Slide to delete \(selected.count)",
              tint: MessagesStyle.danger, height: MessagesStyle.selectionBarHeight
            ) {
              let ids = selected
              withAnimation(reduceMotion ? nil : NessaMotion.enter) {
                selected = []
                if selectingToDelete {
                  editing = false
                  selectingToDelete = false
                }
              }
              delete(ids)
            }
            .padding(.horizontal, MessagesStyle.horizontal)
            .padding(.bottom, MessagesStyle.bottomInset)
            .disabled(deleting || !store.connected)
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
        selectingToDelete = false
      }
      .refreshable {
        do { try await store.refreshList() } catch { store.error = error.localizedDescription }
      }
  }
  /// A single chat's Delete (from its menu or a swipe) uses the same slide as a selection:
  /// select mode opens with just that chat picked, so the slide rises, with no sheet.
  private func selectToDelete(_ id: String) {
    withAnimation(reduceMotion ? nil : NessaMotion.enter) {
      selectingToDelete = !editing
      editing = true
      selected = [id]
    }
  }
  private func cancelDelete() {
    withAnimation(reduceMotion ? nil : NessaMotion.enter) {
      editing = false
      selected = []
      selectingToDelete = false
    }
  }
  private func delete(_ ids: Set<String>) {
    deleting = true
    withAnimation(reduceMotion ? nil : NessaMotion.standard(MessagesStyle.rowFadeOut)) {
      fading.formUnion(ids)
    }
    Task {
      // The gap closes only once the rows have faded: timed rather than waiting on the
      // fade's completion, which can fire at once when the list redraws the rows in the same
      // update (the selection clearing and the bar sinking). The store hides a chat the
      // moment its deletion starts, so the rows leave first, on the layout spring.
      if !reduceMotion { try? await Task.sleep(for: .seconds(MessagesStyle.rowFadeOut)) }
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
