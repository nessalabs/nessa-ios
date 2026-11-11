import SwiftUI

/// Owns the first draft while the gateway allocates a chat. Home and channel entry
/// points pass the captured draft to the thread's normal, recoverable send path.
struct NewChatComposer: View {
  @ObservedObject var store: MessagesViewModel
  @ObservedObject var dictation: DictationViewModel
  let channel: NessaChannel?
  let onStart: (String, HomeFirstMessage) -> Void
  @State private var draft = ""
  @State private var reply: MessageReply?
  @State private var attachments: [DraftAttachment] = []
  @State private var starting = false

  var body: some View {
    let name = channel?.name ?? (store.agentProfiles.count == 1 ? store.agentProfiles[0].displayName : "Nessa")
    MessageComposer(
      draft: $draft, reply: $reply, attachments: $attachments,
      recipient: name, dictation: dictation, sending: starting || store.busy,
      connected: store.connected, attachmentPolicy: store.attachmentPolicy,
      submissionAllowed: store.canCreateChat && !starting,
      placeholder: channel == nil ? "Message \(name) or hold to talk" : "Message \(name)",
      endsEditingOnSend: true, onSend: start)
  }

  private func start() {
    guard !starting else { return }
    starting = true
    let first = HomeFirstMessage(text: draft, attachments: attachments)
    Task {
      defer { starting = false }
      let key = channel.flatMap { $0.isDefault ? nil : $0.channelId }
      guard let id = await store.create(channel: key) else { return }
      first.consume(from: &draft, attachments: &attachments)
      onStart(id, first)
    }
  }
}
