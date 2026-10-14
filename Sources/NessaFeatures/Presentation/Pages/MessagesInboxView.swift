import NessaDesignSystem
import SwiftUI

struct MessagesInboxView: View {
  @ObservedObject var store: MessagesViewModel
  let onSettings: () -> Void
  let onOpen: (String) -> Void
  let onCompose: () -> Void
  let onOpenComposer: (String) -> Void
  @State private var scrollOffset: CGFloat = 0
  @State private var editing = false
  @State private var showingArchived = false
  @State private var selected: Set<String> = []
  @State private var pendingDeletion: Set<String> = []
  @State private var deleting = false
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
            onDelete: { pendingDeletion = [$0] }, enabled: !deleting)
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
              if !selected.insert(conversation.id).inserted { selected.remove(conversation.id) }
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
            // A row leaving (pinned, archived, deleted) collapses inside its own bounds, so
            // its text never slides over the row moving up into its place. The mask is
            // widened sideways only, to keep the selected fill's overhang.
            .mask { Rectangle().padding(.horizontal, -NessaSpacing.xs) }
          }.buttonStyle(.plain)
            .disabled(deleting)
            .accessibilityLabel(
              editing
                ? "Select \(store.chatName(conversation.id))" : store.chatName(conversation.id)
            )
            .accessibilityAddTraits(selected.contains(conversation.id) ? .isSelected : [])
            .chatContextMenu(
              store: store, identifier: conversation.id,
              enabled: !editing && !deleting,
              onTap: { onOpen(conversation.id) }, onCommit: onOpenComposer,
              onDelete: { pendingDeletion = [$0] }
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
                  pendingDeletion = [conversation.id]
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
      .environment(\.defaultMinListRowHeight, 0)
      .messagesTrackScroll(offset: $scrollOffset)
      .sensoryFeedback(.impact(flexibility: .soft), trigger: store.pinnedChats)
      .sensoryFeedback(.warning, trigger: pinRefusals)
      .messagesAmbientGround()
      .messagesScrollEdges()
      .scrollDismissesKeyboard(.interactively)
      .messagesFooterGrain()
      .messagesBar(edge: .top) {
        InboxHeader(
          editing: editing,
          onEdit: {
            // The marks slide in from the edge as the rows make room, on one spring.
            withAnimation(reduceMotion ? nil : NessaMotion.enter) {
              editing.toggle()
              selected = []
            }
          }, onSettings: onSettings, showingArchived: showingArchived,
          onToggleArchived: {
            showingArchived.toggle()
            selected = []
          }
        )
        .disabled(deleting)
        .messagesHeaderGrain()
        .messagesHeaderBlur(scrollOffset: scrollOffset)
      }
      .messagesBar(edge: .bottom) {
        if editing {
          HStack {
            Text("\(selected.count) selected").font(MessagesStyle.body)
              .foregroundStyle(MessagesStyle.secondary)
              .contentTransition(.numericText(value: Double(selected.count)))
              .animation(reduceMotion ? nil : NessaMotion.morph, value: selected.count)
            Spacer()
            Button(role: .destructive) {
              pendingDeletion = selected
            } label: {
              // Only the icon carries the red, so the bar stays as quiet as the list.
              Label {
                Text("Delete").foregroundStyle(MessagesStyle.foreground)
              } icon: {
                Image(systemName: "trash").foregroundStyle(MessagesStyle.danger)
              }
            }
            .font(MessagesStyle.title).buttonStyle(.nessaPress)
            .disabled(selected.isEmpty || deleting || !store.connected)
          }.padding(.horizontal, NessaSpacing.lg).frame(height: MessagesStyle.composerHeight)
            .messagesComposerSurface()
            .padding(.horizontal, MessagesStyle.horizontal).padding(.bottom, MessagesStyle.bottomInset)
            .foregroundStyle(MessagesStyle.foreground)
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
      .sheet(
        isPresented: Binding(
          get: { !pendingDeletion.isEmpty }, set: { if !$0 { pendingDeletion = [] } })
      ) {
        DeleteChatsConfirmation(count: pendingDeletion.count, onCancel: { pendingDeletion = [] }) {
          let ids = pendingDeletion
          pendingDeletion = []
          deleting = true
          Task {
            await store.deleteConversations(ids)
            selected.formIntersection(Set(store.conversations.map(\.id)))
            deleting = false
          }
        }
      }
      .nessaHideNavigationBar()
      .onChange(of: store.connected) { _, _ in
        selected = []
        pendingDeletion = []
        editing = false
      }
      .refreshable {
        do { try await store.refreshList() } catch { store.error = error.localizedDescription }
      }
  }
  /// The pinned chats the grid shows right now, or none while it is hidden.
  private var pinnedShown: [String] {
    guard !editing && !showingArchived && search.isEmpty else { return [] }
    return store.pinnedChats.filter { !store.isDeleting($0) }
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
      (store.archivedChats.contains($0.id) == showingArchived)
        && (editing || showingArchived || !store.isPinned($0.id))
        && (search.isEmpty || ($0.title ?? "").localizedCaseInsensitiveContains(search)
          || ($0.preview ?? "").localizedCaseInsensitiveContains(search))
    }
  }
}
