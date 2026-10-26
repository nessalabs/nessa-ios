import NessaDesignSystem
import SwiftUI

/// Every agent at a glance, as the desktop's Agents overview shows them: what needs the
/// person first, then what is working, what finished, and the rest. A chip narrows the list
/// to one group. A swipe on a chat archives or deletes it, each asked in an alert first.
struct AgentsView: View {
  @ObservedObject var store: MessagesViewModel
  let onOpen: (String) -> Void
  @State private var shown: AgentsGroup?
  /// A Delete or Archive waiting on the system's alert.
  @State private var asking: ChatRemoval?
  /// Chats being deleted or archived. Their rows first fade out where they stand (`fading`),
  /// then leave the list on the layout spring (`leaving`), so the rows below close the gap
  /// through empty space rather than through fading text. The store's own change lands
  /// later, outside any animation, once there is nothing left to see go.
  @State private var fading: Set<String> = []
  @State private var leaving: Set<String> = []
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let glance = store.agentsGlance
    // A row on its way out no longer counts, so a chip never reads one chat it can't show.
    let count = { (group: AgentsGroup) in glance.ids(group).filter { !leaving.contains($0) }.count }
    // A chosen group that has emptied (its last review answered) shows everything again,
    // rather than an empty screen with no chip chosen; the choice itself is cleared below,
    // so a new review does not narrow the list back by itself.
    let showing = shown.flatMap { count($0) > 0 ? $0 : nil }
    // A List, not a stack, for its swipe actions. It carries no implicit animation of its
    // own: an `.animation` on a List mixes into the collection view's row updates, so every
    // change it should animate goes through `withAnimation`.
    List {
      Group {
        chips(count, showing: showing)
        if store.pendingLoadError != nil { PendingDeliveryUnavailable(store: store) }
        ForEach(store.pendingCreations, id: \.requestID) { command in
          PendingCommandActions(command: command, store: store, onCreated: onOpen)
        }
        ForEach(AgentsGroup.allCases, id: \.self) { group in
          let ids = glance.ids(group).filter { !leaving.contains($0) }
          if !ids.isEmpty && (showing == nil || showing == group) {
            Text(group.title).font(MessagesStyle.sidebarSection)
              .foregroundStyle(MessagesStyle.secondary)
              .padding(.horizontal, MessagesStyle.horizontal)
              .padding(.top, MessagesStyle.agentsSectionGap).padding(.bottom, NessaSpacing.xs)
              .accessibilityAddTraits(.isHeader)
            ForEach(ids, id: \.self) { id in
              Group {
                if group == .needsYou, let permission = store.waitingPermission(in: id) {
                  approval(id, permission: permission)
                } else {
                  row(id, group: group)
                }
              }
              .opacity(fading.contains(id) ? 0 : 1)
              // A row leaving collapses inside its own bounds, so its text never slides over
              // the row moving up into its place.
              .mask { Rectangle() }
              .swipeActions(edge: .trailing, allowsFullSwipe: false) { removals(id) }
            }
          }
        }
        if !store.listComplete {
          Text("Some conversations could not be listed.").font(MessagesStyle.caption)
            .foregroundStyle(MessagesStyle.secondary)
            .padding(.horizontal, MessagesStyle.horizontal).padding(.top, NessaSpacing.md)
        }
      }
      .listRowInsets(EdgeInsets())
      .listRowSeparator(.hidden)
      .listRowBackground(Color.clear)
    }
    .listStyle(.plain)
    .scrollContentBackground(.hidden)
    .environment(\.defaultMinListRowHeight, 0)
    .contentMargins(.bottom, NessaSpacing.xl, for: .scrollContent)
    .onChange(of: showing) { _, now in if now == nil { shown = nil } }
    .refreshable {
      // A paired Mac that dropped is tried again; a live connection reads its list afresh.
      guard store.connected else { return await store.reconnectLinked() }
      do { try await store.refreshList() } catch { store.error = error.localizedDescription }
    }
    .onChange(of: store.connected) { _, _ in asking = nil }
    // An alert, centred with its own Cancel: a confirmation dialog on iOS 26 is a popover
    // anchored to the list, pointing at none of the rows that asked.
    .alert(asking?.title ?? "", isPresented: askingShown, presenting: asking) { ask in
      Button(ask.verb, role: ask.action == .delete ? .destructive : nil) { perform(ask) }
        .disabled(ask.action == .delete && !canDelete)
      Button("Cancel", role: .cancel) {}
    } message: { ask in
      if ask.action == .delete { Text("This can't be undone.") }
    }
    .messagesScrollEdges()
    .messagesAmbientGround()
    // The title sits in the bar beside the back button, not as a large title under it, so
    // the list starts higher.
    .navigationTitle("Agents")
    .nessaInlineNavigationTitle()
    .toolbar { BarTitle("Agents") }
  }

  /// Each asks first; nothing goes on one swipe.
  @ViewBuilder private func removals(_ id: String) -> some View {
    Button {
      ask(id, .delete)
    } label: {
      Label("Delete", systemImage: "trash")
    }
    .tint(MessagesStyle.danger)
    .disabled(!canDelete)
    // Archived chats come back from Settings, under Archived chats.
    Button("Archive", systemImage: "archivebox") { ask(id, .archive) }
      .tint(MessagesStyle.archiveAction)
      .disabled(!store.connected)
  }

  private var canDelete: Bool { store.connected && store.conversationAuthorityReady }

  private var askingShown: Binding<Bool> {
    Binding(get: { asking != nil }, set: { if !$0 { asking = nil } })
  }

  private func ask(_ id: String, _ action: ChatRemoval.Action) {
    // Asked on the next turn of the run loop, after the swipe that asked has begun closing:
    // presented in the same update, the alert could be dropped.
    Task { asking = ChatRemoval(id: id, action: action) }
  }

  private func perform(_ ask: ChatRemoval) {
    let id = ask.id
    // Fades the row out where it stands, then takes it away. Timed rather than waiting on the
    // fade's completion, which can fire at once when the list redraws the row.
    withAnimation(reduceMotion ? nil : NessaMotion.standard(MessagesStyle.rowFadeOut)) {
      _ = fading.insert(id)
    }
    Task {
      if !reduceMotion { try? await Task.sleep(for: .seconds(MessagesStyle.rowFadeOut)) }
      withAnimation(reduceMotion ? nil : NessaMotion.enter) { _ = leaving.insert(id) }
      switch ask.action {
      case .delete:
        // The store hides a chat the moment its deletion starts.
        await store.deleteConversations([id])
      case .archive:
        // The store moves the chat only once the list has closed up, outside any animation,
        // so its update can't jolt the list mid-close.
        try? await Task.sleep(for: .seconds(MessagesStyle.rowSettle))
        await store.setArchived(true, conversationID: id)
      }
      // A chat the gateway kept comes back on the same spring.
      withAnimation(reduceMotion ? nil : NessaMotion.enter) {
        leaving.remove(id)
        fading.remove(id)
      }
    }
  }

  private func approval(_ id: String, permission: NessaPermission) -> some View {
    let channel = store.conversations.first { $0.id == id }?.channelId
    let channelName = store.channels.first { $0.id == channel && !$0.isDefault }?.name
    return PermissionCard(
      permission: permission,
      source: .init(chatName: store.chatName(id), channelName: channelName, onOpen: { onOpen(id) })
    ) { option in Task { await store.answer(permission, option: option, in: id) } }
    .padding(.horizontal, MessagesStyle.agentsCardGutter)
  }

  private func chips(_ count: (AgentsGroup) -> Int, showing: AgentsGroup?) -> some View {
    ScrollView(.horizontal) {
      HStack(spacing: NessaSpacing.xs) {
        chip("All", selected: showing == nil) { shown = nil }
        ForEach(AgentsGroup.allCases, id: \.self) { group in
          let count = count(group)
          if count > 0 {
            chip("\(group.title) \(count)", selected: showing == group) {
              shown = showing == group ? nil : group
            }
          }
        }
      }
      .padding(.horizontal, MessagesStyle.horizontal)
    }
    .scrollIndicators(.hidden)
    // The list's bottom margin is for its own end, not this row's.
    .contentMargins(.bottom, 0, for: .scrollContent)
    .padding(.top, NessaSpacing.sm)
  }

  private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
    Button {
      withAnimation(reduceMotion ? nil : NessaMotion.standard()) { action() }
    } label: {
      Text(title).font(MessagesStyle.preview.weight(selected ? .semibold : .regular))
        .padding(.horizontal, MessagesStyle.chipInset)
        .frame(height: MessagesStyle.chipHeight)
        .foregroundStyle(selected ? MessagesStyle.background : MessagesStyle.foreground)
        .background(
          selected ? AnyShapeStyle(MessagesStyle.foreground) : AnyShapeStyle(NessaColor.card),
          in: Capsule())
        .overlay(Capsule().stroke(NessaColor.hairline, lineWidth: selected ? 0 : 1))
    }
    .buttonStyle(.nessaPress)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private func row(_ id: String, group: AgentsGroup) -> some View {
    let conversation = store.conversations.first { $0.id == id }
    return Button { onOpen(id) } label: {
      HStack(spacing: MessagesStyle.agentsRowGap) {
        NessaIcon(.chats, size: MessagesStyle.rowIcon)
          .foregroundStyle(group == .earlier ? MessagesStyle.secondary : MessagesStyle.foreground)
        VStack(alignment: .leading, spacing: MessagesStyle.rowLineGap) {
          Text(store.chatName(id)).font(MessagesStyle.sidebarRow)
            .fontWeight(group == .finished ? .semibold : .regular)
            .lineLimit(1)
          Text(detail(conversation, group: group)).font(MessagesStyle.preview)
            .foregroundStyle(MessagesStyle.secondary).lineLimit(1)
            .nessaShimmer(active: group == .working)
        }
        Spacer(minLength: 0)
        if group == .needsYou || group == .working {
          Circle().fill(NessaColor.accent)
            .frame(width: MessagesStyle.statusDot, height: MessagesStyle.statusDot)
        }
      }
      .foregroundStyle(MessagesStyle.foreground)
      .padding(.horizontal, MessagesStyle.horizontal)
      .padding(.vertical, MessagesStyle.agentsRowInset)
      .contentShape(Rectangle())
    }
    .buttonStyle(.nessaPress)
    .accessibilityLabel("\(store.chatName(id)), \(group.title)")
  }

  private func detail(_ conversation: NessaConversation?, group: AgentsGroup) -> String {
    switch group {
    case .needsYou: return "Waiting for your answer"
    case .working: return "\(store.agentName(for: conversation?.id ?? "")) is working…"
    case .finished, .earlier: return conversation?.preview ?? "New conversation"
    }
  }
}

/// A chat waiting on the alert, and what will happen to it.
private struct ChatRemoval {
  enum Action { case delete, archive }
  let id: String
  let action: Action
  var verb: String { action == .delete ? "Delete" : "Archive" }
  var title: String { "\(verb) this chat?" }
}
