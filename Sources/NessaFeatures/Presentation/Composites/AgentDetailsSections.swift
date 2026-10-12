import NessaDesignSystem
import SwiftUI

struct AgentDetailsSection<Content: View>: View {
  let title: String
  @ViewBuilder let content: () -> Content
  var body: some View {
    VStack(alignment: .leading, spacing: NessaSpacing.sm) {
      Text(title).font(MessagesStyle.title)
      content().font(MessagesStyle.body)
    }.frame(maxWidth: .infinity, alignment: .leading)
      .padding(NessaSpacing.md)
      .background(MessagesStyle.control, in: RoundedRectangle(cornerRadius: NessaRadius.xl))
  }
}

extension AgentDetailsSection where Content == Text {
  init(title: String, text: String) {
    self.title = title
    self.content = { Text(text) }
  }
}

struct AgentOverview: View {
  let profile: AgentProfile?
  var body: some View {
    if let prompt = profile?.prompt, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      AgentDetailsSection(title: "Agent prompt") {
        Text(prompt).textSelection(.enabled)
      }
    }
    AgentDetailsSection(title: "Access granted") {
      if let access = profile?.grantedAccess {
        if access.isEmpty {
          Text("No granted access reported.")
        } else {
          ForEach(Array(access.enumerated()), id: \.offset) { _, item in
            Label(item, systemImage: "checkmark.shield")
          }
        }
      } else {
        Text(
          "The connected service hasn’t supplied a granted-access list. Pending requests appear in Activity."
        )
      }
    }
  }
}

struct AgentArtifacts: View {
  let conversation: NessaConversationView?
  @ObservedObject var store: MessagesViewModel
  var body: some View {
    let artifacts = ConversationArtifact.collect(from: conversation?.messages ?? [])
    if conversation == nil {
      AgentDetailsSection(
        title: "Artifacts unavailable", text: "Conversation history hasn’t loaded yet.")
    } else if artifacts.isEmpty {
      AgentDetailsSection(
        title: "No artifacts yet",
        text: "Images and files will appear here.")
    } else {
      LazyVStack(alignment: .leading, spacing: NessaSpacing.md) {
        ForEach(artifacts) { artifact in
          switch artifact.content {
          case .image(let image):
            PhotoAttachment(id: artifact.id) { await store.imageData(for: image) }
          case .file(let file):
            AgentFileArtifact(file: file)
          }
        }
      }
    }
  }
}

struct AgentActivity: View {
  let conversation: NessaConversationView?
  var body: some View {
    if let conversation {
      if conversation.messages.isEmpty && conversation.permissions.isEmpty {
        Text("No activity yet.")
          .font(MessagesStyle.body).foregroundStyle(MessagesStyle.secondary)
      } else {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(conversation.permissions) { permission in
            AgentActivityRow(title: permission.title, status: "Access requested")
          }
          ForEach(conversation.messages.reversed()) { turn in
            AgentActivityRow(
              title: turn.userText.isEmpty ? "Conversation turn" : turn.userText,
              status: turn.status.capitalized,
              detail: turn.error ?? turn.bubbles.last,
              hasError: turn.error != nil
            )
          }
        }
      }
    } else {
      Text("Conversation history hasn’t loaded yet.")
        .font(MessagesStyle.body).foregroundStyle(MessagesStyle.secondary)
    }
  }
}

private struct AgentActivityRow: View {
  let title: String
  let status: String
  var detail: String?
  var hasError = false
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      VStack(alignment: .leading, spacing: NessaSpacing.xs) {
        HStack(alignment: .firstTextBaseline, spacing: NessaSpacing.sm) {
          Text(title).font(MessagesStyle.body).lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
          Text(status).font(MessagesStyle.caption)
            .foregroundStyle(MessagesStyle.secondary).fixedSize(horizontal: true, vertical: false)
        }
        if let detail {
          Text(detail).font(MessagesStyle.caption).lineLimit(hasError ? 2 : 1)
            .foregroundStyle(hasError ? MessagesStyle.danger : MessagesStyle.secondary)
        }
      }.padding(.vertical, NessaSpacing.sm)
      Divider().overlay(MessagesStyle.separator)
    }.accessibilityElement(children: .combine)
  }
}
