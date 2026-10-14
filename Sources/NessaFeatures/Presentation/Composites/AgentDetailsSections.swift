import NessaDesignSystem
import SwiftUI

/// A Nessa card with a small labelled heading: an icon in the accent ink and a quiet caps title.
struct AgentDetailsSection<Content: View>: View {
  let title: String
  var symbol = "circle.grid.2x2"
  @ViewBuilder let content: () -> Content
  var body: some View {
    VStack(alignment: .leading, spacing: NessaSpacing.sm) {
      Label {
        Text(title.uppercased()).tracking(AgentDetailsStyle.sectionLabelTracking)
      } icon: {
        Image(systemName: symbol)
      }
      .font(AgentDetailsStyle.sectionLabel).foregroundStyle(MessagesStyle.secondary)
      .accessibilityAddTraits(.isHeader)
      content().font(MessagesStyle.body).foregroundStyle(MessagesStyle.foreground)
    }.frame(maxWidth: .infinity, alignment: .leading)
      .padding(NessaSpacing.md)
      .nessaCard()
  }
}

extension AgentDetailsSection where Content == Text {
  init(title: String, symbol: String = "info.circle", text: String) {
    self.title = title
    self.symbol = symbol
    self.content = { Text(text) }
  }
}

struct AgentOverview: View {
  let profile: AgentProfile?
  var body: some View {
    if let prompt = profile?.prompt, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      AgentDetailsSection(title: "Agent prompt", symbol: "text.quote") {
        Text(prompt).textSelection(.enabled).lineSpacing(NessaSpacing.xxs)
      }
    }
    AgentDetailsSection(title: "Access granted", symbol: "checkmark.shield") {
      if let access = profile?.grantedAccess {
        if access.isEmpty {
          Text("No granted access reported.").foregroundStyle(MessagesStyle.secondary)
        } else {
          VStack(alignment: .leading, spacing: NessaSpacing.xs) {
            ForEach(Array(access.enumerated()), id: \.offset) { _, item in
              Label {
                Text(item)
              } icon: {
                Image(systemName: "checkmark").foregroundStyle(MessagesStyle.secondary)
              }
            }
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
        title: "Artifacts unavailable", symbol: "hourglass",
        text: "Conversation history hasn’t loaded yet.")
    } else if artifacts.isEmpty {
      AgentDetailsSection(
        title: "No artifacts yet", symbol: "square.stack",
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
        AgentDetailsSection(
          title: "No activity yet", symbol: "waveform.path",
          text: "Turns and access requests will appear here.")
      } else {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(conversation.permissions) { permission in
            AgentActivityRow(title: permission.title, state: .requested)
          }
          ForEach(conversation.messages.reversed()) { turn in
            AgentActivityRow(
              title: turn.userText.isEmpty ? "Conversation turn" : turn.userText,
              state: AgentActivityState(status: turn.status, failed: turn.error != nil),
              detail: turn.error ?? turn.bubbles.last
            )
          }
        }
        .padding(.vertical, NessaSpacing.xs)
        .padding(.horizontal, NessaSpacing.md)
        .nessaCard()
      }
    } else {
      AgentDetailsSection(
        title: "Activity unavailable", symbol: "hourglass",
        text: "Conversation history hasn’t loaded yet.")
    }
  }
}

/// What a row in the activity timeline is doing, in words a person reads.
enum AgentActivityState: Equatable {
  case working, done, failed, requested, other(String)
  init(status: String, failed: Bool) {
    if failed {
      self = .failed
    } else {
      switch status {
      case "running": self = .working
      case "completed", "complete", "done", "succeeded": self = .done
      default: self = .other(status.capitalized)
      }
    }
  }
  var label: String {
    switch self {
    case .working: "Working"
    case .done: "Done"
    case .failed: "Failed"
    case .requested: "Access requested"
    case .other(let text): text
    }
  }
  var tint: Color {
    switch self {
    case .working: MessagesStyle.foreground
    case .done: MessagesStyle.secondary
    case .failed: MessagesStyle.danger
    case .requested: MessagesStyle.foreground
    case .other: MessagesStyle.secondary
    }
  }
}

/// One stop on the timeline: a dot on a running line, the turn, and its state.
private struct AgentActivityRow: View {
  let title: String
  let state: AgentActivityState
  var detail: String?
  var body: some View {
    HStack(alignment: .top, spacing: NessaSpacing.sm) {
      Circle().fill(state.tint)
        .frame(width: AgentDetailsStyle.timelineDot, height: AgentDetailsStyle.timelineDot)
        .padding(.top, NessaSpacing.md + NessaSpacing.xxs)
        .frame(width: AgentDetailsStyle.timelineGutter)
      VStack(alignment: .leading, spacing: NessaSpacing.xxs) {
        HStack(alignment: .firstTextBaseline, spacing: NessaSpacing.sm) {
          Text(title).font(MessagesStyle.body).lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
          NessaChip(state.label, tint: state.tint).fixedSize()
        }
        if let detail {
          Text(detail).font(MessagesStyle.caption).lineLimit(state == .failed ? 2 : 1)
            .foregroundStyle(state == .failed ? MessagesStyle.danger : MessagesStyle.secondary)
        }
      }.padding(.vertical, NessaSpacing.sm)
    }
    // The line runs the full height of the row behind the dot, joining it to its neighbours.
    .background(alignment: .leading) {
      Rectangle().fill(MessagesStyle.rowSeparator)
        .frame(width: AgentDetailsStyle.timelineLine)
        .padding(.leading, (AgentDetailsStyle.timelineGutter - AgentDetailsStyle.timelineLine) / 2)
    }
    .accessibilityElement(children: .combine)
  }
}
