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
        if !editing && !showingArchived
          && store.pinnedChats.contains(where: { !store.isDeleting($0) }) && search.isEmpty
        {
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
                Button(
                  store.isPinned(conversation.id) ? "Unpin" : "Pin",
                  systemImage: store.isPinned(conversation.id) ? "pin.slash.fill" : "pin.fill"
                ) {
                  store.togglePin(conversation.id)
                }.tint(MessagesStyle.pinAction).disabled(!store.canTogglePin(conversation.id))
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
                  store.setArchived(!showingArchived, conversationID: conversation.id)
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
      .animation(reduceMotion ? nil : NessaMotion.enter, value: filtered.map(\.id))
      .messagesAmbientGround()
      .messagesScrollEdges()
      .scrollDismissesKeyboard(.interactively)
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
  private var filtered: [NessaConversation] {
    store.visibleConversations.filter {
      (store.archivedChats.contains($0.id) == showingArchived)
        && (editing || showingArchived || !store.isPinned($0.id))
        && (search.isEmpty || ($0.title ?? "").localizedCaseInsensitiveContains(search)
          || ($0.preview ?? "").localizedCaseInsensitiveContains(search))
    }
  }
}
