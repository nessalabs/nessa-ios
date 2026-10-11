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

  var body: some View {
    VStack(spacing: NessaSpacing.xs) {
      header
      ScrollView {
        LazyVStack(alignment: .leading, spacing: NessaSpacing.md, pinnedViews: [.sectionHeaders]) {
          AgentDetailsIdentity(name: name, compact: false)
            .scaleEffect(
              reduceMotion ? 1 : 1 - collapse * (1 - AgentDetailsStyle.collapsedScale),
              anchor: .leading
            )
            .opacity(1 - collapse)
            .accessibilityHidden(collapse >= 1)
          Section {
            content
          } header: {
            AgentDetailsTabs(selection: $tab)
              .padding(.bottom, NessaSpacing.sm)
              .background(MessagesStyle.background)
          }
        }.padding(.bottom, NessaSpacing.md)
      }
      .onScrollGeometryChange(for: CGFloat.self) { geometry in
        min(1, max(0, geometry.contentOffset.y + geometry.contentInsets.top)
          / AgentDetailsStyle.collapseDistance)
      } action: { _, progress in
        collapse = progress
      }
    }.padding(.horizontal, MessagesStyle.horizontal)
      .padding(.top, NessaSpacing.sm)
      .foregroundStyle(MessagesStyle.foreground).background(MessagesStyle.background)
      .presentationDragIndicator(.hidden)
  }

  private var header: some View {
    HStack(spacing: NessaSpacing.sm) {
      AgentDetailsIdentity(name: name, compact: true)
        .opacity(collapse)
        .accessibilityHidden(collapse < 1)
      Spacer(minLength: NessaSpacing.xs)
      Button("Done") { dismiss() }
        .font(MessagesStyle.title).padding(.horizontal, NessaSpacing.md)
        .frame(minHeight: MessagesStyle.controlHeight).messagesGlass()
    }.frame(minHeight: MessagesStyle.controlHeight)
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
