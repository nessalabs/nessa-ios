import NessaDesignSystem
import SwiftUI

struct AgentDetailsView: View {
  let name: String
  let conversationID: String
  @ObservedObject var store: MessagesViewModel
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var tab = AgentDetailsTab.overview
  @State private var collapse: CGFloat = 0
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
        AgentDetailsHero(name: name, profile: profile, working: working)
          .opacity(1 - collapse)
          .scaleEffect(
            reduceMotion ? 1 : 1 - collapse * (1 - AgentDetailsStyle.collapsedScale),
            anchor: .leading
          )
          .accessibilityHidden(collapse >= 1)
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
    .onScrollGeometryChange(for: CGFloat.self) { geometry in
      min(1, max(0, geometry.contentOffset.y + geometry.contentInsets.top)
        / AgentDetailsStyle.collapseDistance)
    } action: { _, progress in
      collapse = progress
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
      AgentDetailsIdentity(name: name)
        .opacity(collapse)
        .accessibilityHidden(collapse < 1)
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
