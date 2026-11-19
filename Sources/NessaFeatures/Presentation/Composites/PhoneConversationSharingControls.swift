import NessaDesignSystem
import SwiftUI

/// The owner picker remains separate from the phone's retained conversation list.
struct PhoneConversationSharingControls: View {
  @ObservedObject var store: MessagesViewModel
  var conversationID: String? = nil
  private var idle: Bool { store.connected && !store.busy && !store.phoneSetupBusy }
  private var pending: [PhoneConversationShareIntent] {
    store.pendingPhoneShares.filter { conversationID == nil || $0.conversationID == conversationID }
  }
  var body: some View {
    if let conversationID {
      action("Sync this conversation", .share(conversationID))
    } else {
      action("Choose conversations", .choices)
      if let choices = store.phoneOwnerChoices {
        ForEach(choices.conversations) { conversation in
          VStack(alignment: .leading, spacing: NessaSpacing.xxs) {
            action("Sync \(conversation.title ?? "Untitled conversation")", .share(conversation.id))
            Text(conversation.id).font(MessagesStyle.caption.monospaced())
              .foregroundStyle(MessagesStyle.secondary).textSelection(.enabled)
          }
        }
        if choices.conversations.isEmpty {
          Text("No conversations returned.").font(MessagesStyle.caption)
        }
        if !choices.complete {
          Text("More conversations may be available.").font(MessagesStyle.caption)
        }
      }
    }
    ForEach(pending, id: \.requestID) { intent in
      VStack(alignment: .leading, spacing: NessaSpacing.xs) {
        Text("Pending share").font(MessagesStyle.caption)
        Text(intent.conversationID).font(MessagesStyle.caption.monospaced()).textSelection(.enabled)
        action("Check current sharing", .check(intent))
        action("Retry original request", .retry(intent))
      }
    }
    if store.phoneSetupBusy { ProgressView("Updating phone sync…") }
    if let message = store.phoneSharingMessage { Text(message).font(MessagesStyle.caption) }
    if let error = store.phoneSharingLoadError { Text(error).font(MessagesStyle.caption) }
  }
  private func action(_ title: String, _ operation: PhoneConversationSharingOperation) -> some View
  {
    Button(title) { Task { await store.performConversationSharing(operation) } }
      .disabled(!idle)
  }
}

struct PhoneConversationSharingSection: View {
  @ObservedObject var store: MessagesViewModel
  var conversationID: String? = nil
  var body: some View {
    Section {
      PhoneConversationSharingControls(store: store, conversationID: conversationID)
    } header: {
      Text("Conversations on this phone")
    } footer: {
      Text("Sync gives this device Read access. It can replace access changed elsewhere.")
    }
  }
}

struct PhoneConversationSharingView: View {
  @ObservedObject var store: MessagesViewModel
  let conversationID: String
  @Environment(\.dismiss) private var dismiss
  var body: some View {
    NavigationStack {
      Form { PhoneConversationSharingSection(store: store, conversationID: conversationID) }
        .navigationTitle("Phone sync")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
    }
  }
}
