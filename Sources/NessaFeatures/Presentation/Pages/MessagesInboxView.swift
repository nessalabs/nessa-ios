import NessaDesignSystem
import SwiftUI

struct MessagesInboxView: View {
  @ObservedObject var store: MessagesViewModel
  let onSettings: () -> Void
  let onOpen: (String) -> Void
  let onCompose: () -> Void
  @State private var scrollOffset: CGFloat = 0
  @State private var editing = false
  @State private var showingArchived = false
  @State private var selected: Set<String> = []
  @State private var pendingDeletion: Set<String> = []
  @State private var deleting = false
  @State private var search = ""
  var body: some View {
    List {
      Group {
        if store.pendingLoadError != nil { PendingDeliveryUnavailable(store: store) }
        ForEach(store.pendingCreations, id: \.requestID) { command in
          PendingCommandActions(command: command, store: store, onCreated: onOpen)
        }
        if !editing && !showingArchived
          && store.pinnedChats.contains(where: { !store.isDeleting($0) }) && search.isEmpty
        {
          PinnedChatsGrid(store: store, onOpen: onOpen)
        }
        if !store.connected {
          Button(store.reconnecting ? "Reconnecting…" : "Connect to Nessa", action: onSettings)
            .font(MessagesStyle.body).padding(NessaSpacing.xl)
        } else if store.visibleConversations.isEmpty {
          VStack(spacing: NessaSpacing.sm) {
            Text("Your chats, one message away.").font(MessagesStyle.title)
            Button("New message", action: onCompose).font(MessagesStyle.body)
              .disabled(store.pendingLoadError != nil || !store.pendingCreations.isEmpty)
          }.padding(.vertical, NessaSpacing.xl)
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
                Image(
                  systemName: selected.contains(conversation.id)
                    ? "checkmark.circle.fill" : "circle"
                )
                .font(MessagesStyle.icon).foregroundStyle(MessagesStyle.outgoing)
              }
              ConversationRow(
                conversation: conversation, agentName: store.agentName(for: conversation.id))
            }.contentShape(Rectangle())
          }.buttonStyle(.plain)
            .disabled(deleting)
            .accessibilityLabel(
              editing
                ? "Select \(store.chatName(conversation.id))" : store.chatName(conversation.id)
            )
            .accessibilityAddTraits(selected.contains(conversation.id) ? .isSelected : [])
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
                }.tint(MessagesStyle.danger).disabled(!store.connected)
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
      .listRowSeparator(.hidden).listRowBackground(MessagesStyle.background)
    }.listStyle(.plain).scrollContentBackground(.hidden)
      .environment(\.defaultMinListRowHeight, 0)
      .messagesTrackScroll(offset: $scrollOffset)
      .background(MessagesStyle.background)
      .messagesScrollEdges()
      .scrollDismissesKeyboard(.interactively)
      .messagesBar(edge: .top) {
        InboxHeader(
          editing: editing,
          onEdit: {
            editing.toggle()
            selected = []
          }, onSettings: onSettings, showingArchived: showingArchived,
          onToggleArchived: {
            showingArchived.toggle()
            selected = []
          }
        )
        .disabled(deleting)
        .messagesHeaderBlur(scrollOffset: scrollOffset)
      }
      .messagesBar(edge: .bottom) {
        if editing {
          HStack {
            Text("\(selected.count) selected").font(MessagesStyle.body)
            Spacer()
            Button(role: .destructive) {
              pendingDeletion = selected
            } label: {
              Label("Delete", systemImage: "trash")
            }
            .font(MessagesStyle.title).foregroundStyle(MessagesStyle.danger)
            .disabled(selected.isEmpty || deleting || !store.connected)
          }.padding(MessagesStyle.horizontal).foregroundStyle(MessagesStyle.foreground)
        } else {
          HStack(spacing: MessagesStyle.toolbarGap) {
            HStack(spacing: NessaSpacing.xs) {
              Image(systemName: "magnifyingglass").font(MessagesStyle.icon)
              TextField("Search", text: $search).font(MessagesStyle.body)
            }.padding(.horizontal, NessaSpacing.md).frame(height: MessagesStyle.composerHeight)
              .messagesGlass()
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
            }.disabled(
              !store.connected || store.busy || store.pendingLoadError != nil
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
