import NessaDesignSystem
import SwiftUI

struct AgentDetailsView: View {
  let name: String
  let conversationID: String
  @ObservedObject var store: MessagesViewModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var tab = AgentDetailsTab.overview
  private var conversation: NessaConversationView? { store.views[conversationID] }
  private var profile: AgentProfile? {
    let id = conversation?.runtime?.agent ?? store.agentID(for: conversationID)
    return store.agentProfiles.first { $0.id == id }
  }

  private var working: Bool {
    conversation?.messages.contains { $0.status == "running" } == true
  }

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: NessaSpacing.lg, pinnedViews: [.sectionHeaders]) {
        let summary = AgentDetailsSummary(profile: profile, working: working)
        if summary.hasContent { summary }
        Section {
          content
            .id(tab)
            .transition(
              .asymmetric(
                insertion: .opacity.combined(with: .offset(y: AgentDetailsStyle.tabSwapDistance)),
                removal: .opacity))
        } header: {
          AgentDetailsTabs(selection: $tab)
            .padding(.vertical, NessaSpacing.xs)
        }
      }
      .padding(.horizontal, MessagesStyle.horizontal)
      .padding(.bottom, NessaSpacing.xl)
      .animation(reduceMotion ? nil : NessaMotion.morph, value: tab)
      .animation(reduceMotion ? nil : NessaMotion.morph, value: working)
    }
    .messagesScrollEdges()
    .messagesBar(edge: .top) { header.messagesHeaderGrain() }
    .foregroundStyle(MessagesStyle.foreground)
    .messagesAmbientGround()
    .presentationDragIndicator(.visible)
    .presentationBackground(MessagesStyle.background)
    .presentationCornerRadius(AgentDetailsStyle.cardRadius * 2)
  }

  private var header: some View {
    HStack(spacing: NessaSpacing.sm) {
      // The agent and the close button share one row and one centre line.
      AgentDetailsIdentity(name: name, seed: conversationID, working: working)
      Spacer(minLength: NessaSpacing.xs)
      Button { dismiss() } label: {
        Image(systemName: "xmark").font(MessagesStyle.icon)
          .frame(width: MessagesStyle.controlHeight, height: MessagesStyle.controlHeight)
          .messagesGlass()
      }
      .buttonStyle(.nessaPress)
      .accessibilityLabel("Close details")
    }
    .frame(minHeight: MessagesStyle.controlHeight)
    .padding(.horizontal, MessagesStyle.horizontal)
    .padding(.top, NessaSpacing.sm)
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: NessaSpacing.lg) {
      if let conversation, conversation.truncated {
        Text("Showing the conversation history supplied by Nessa. Earlier items may be missing.")
          .font(MessagesStyle.caption).foregroundStyle(MessagesStyle.secondary)
      }
      if let error = conversation?.interactionViewError {
        AgentDetailsSection(title: "Conversation unavailable", text: error)
      }
      switch tab {
      case .overview: AgentOverview(profile: profile)
      case .artifacts: AgentArtifacts(conversation: conversation, store: store)
      case .activity: AgentActivity(conversation: conversation)
      }
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
}

enum AgentDetailsTab: String, CaseIterable, Identifiable {
  case overview = "Overview", artifacts = "Artifacts", activity = "Activity"
  var id: Self { self }
}
