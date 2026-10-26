import NessaDesignSystem
import SwiftUI

/// A chat's waiting permission review, answered from the Agents view without opening the
/// chat: whose it is, what it asks, the exact request, and its options as buttons.
struct AgentsApprovalCard: View {
  let chatName: String
  /// The channel the chat is in, beside its name; nil in the default channel.
  let channelName: String?
  let permission: NessaPermission
  let onOpen: () -> Void
  let onAnswer: (NessaPermission.Option) -> Void

  var body: some View {
    let card = RoundedRectangle(cornerRadius: AgentsApprovalStyle.radius, style: .continuous)
    VStack(alignment: .leading, spacing: AgentsApprovalStyle.gap) {
      Button(action: onOpen) {
        VStack(alignment: .leading, spacing: NessaSpacing.xxs) {
          HStack(spacing: NessaSpacing.xs) {
            Text(chatName).font(MessagesStyle.sidebarRow.weight(.semibold)).lineLimit(1)
            Spacer(minLength: 0)
            if let channelName {
              Text(channelName).font(MessagesStyle.preview)
                .foregroundStyle(MessagesStyle.secondary).lineLimit(1)
            }
          }
          Text(permission.title).font(MessagesStyle.preview)
            .foregroundStyle(MessagesStyle.secondary).lineLimit(2)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.nessaPress)
      // The exact request, never a summary of it: what is allowed is what is shown.
      Text(permission.argumentsJson).font(NessaType.mono).lineSpacing(3)
        .lineLimit(AgentsApprovalStyle.requestLines).truncationMode(.tail)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, NessaSpacing.sm).padding(.vertical, NessaSpacing.sm)
        .background(
          .white.opacity(0.06),
          in: RoundedRectangle(cornerRadius: AgentsApprovalStyle.requestRadius, style: .continuous))
      // Two answers sit side by side; more stack, each a whole row.
      let layout = permission.options.count > 2
        ? AnyLayout(VStackLayout(spacing: NessaSpacing.xs))
        : AnyLayout(HStackLayout(spacing: NessaSpacing.xs))
      layout {
        ForEach(ordered) { option in
          let primary = option.id == brightest?.id
          Button { onAnswer(option) } label: {
            Text(option.label).font(MessagesStyle.body.weight(primary ? .semibold : .medium))
              .lineLimit(1).minimumScaleFactor(0.8)
              .frame(maxWidth: .infinity).frame(height: AgentsApprovalStyle.buttonHeight)
              .foregroundStyle(primary ? MessagesStyle.background : MessagesStyle.foreground)
              .background(primary ? MessagesStyle.foreground : NessaColor.muted, in: Capsule())
          }
          .buttonStyle(.nessaPress)
        }
      }
      .padding(.top, NessaSpacing.xxs)
    }
    .padding(.horizontal, AgentsApprovalStyle.inset)
    .padding(.top, AgentsApprovalStyle.inset + NessaSpacing.xxs)
    .padding(.bottom, AgentsApprovalStyle.inset)
    .background(MessagesStyle.incoming, in: card)
    .overlay(card.strokeBorder(NessaColor.hairline, lineWidth: 1))
  }
}

extension AgentsApprovalCard {
  /// Refusals first, then what lets the agent go on, so going on is always on the same side.
  var ordered: [NessaPermission.Option] {
    permission.options.filter { $0.effect != "allow" }
      + permission.options.filter { $0.effect == "allow" }
  }
  /// The narrowest allowing answer is the bright one: the first the agent offered.
  var brightest: NessaPermission.Option? { permission.options.first { $0.effect == "allow" } }
}

private enum AgentsApprovalStyle {
  static let radius: CGFloat = 26
  static let inset: CGFloat = 18
  static let gap: CGFloat = 14
  static let requestRadius: CGFloat = 12
  static let requestLines = 4
  static let buttonHeight: CGFloat = 46
}
