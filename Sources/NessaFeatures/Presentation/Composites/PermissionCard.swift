import NessaDesignSystem
import SwiftUI

/// A waiting permission review, answered in place: what it asks, the exact request, and its
/// options as buttons. In a chat it stands alone; in the Agents view it also names the chat
/// it waits in, and that name opens the chat.
struct PermissionCard: View {
  /// The chat it waits in, its channel (nil in the default one), and how to open it.
  struct Source {
    let chatName: String
    let channelName: String?
    let onOpen: () -> Void
  }
  let permission: NessaPermission
  var source: Source? = nil
  let onAnswer: (NessaPermission.Option) -> Void

  var body: some View {
    let card = RoundedRectangle(cornerRadius: PermissionCardStyle.radius, style: .continuous)
    VStack(alignment: .leading, spacing: PermissionCardStyle.gap) {
      if let source {
        Button(action: source.onOpen) {
          VStack(alignment: .leading, spacing: NessaSpacing.xxs) {
            HStack(spacing: NessaSpacing.xs) {
              Text(source.chatName).font(MessagesStyle.sidebarRow.weight(.semibold))
                .lineLimit(1)
              Spacer(minLength: 0)
              if let channelName = source.channelName {
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
      } else {
        Text(permission.title).font(MessagesStyle.sidebarRow.weight(.semibold)).lineLimit(2)
          .accessibilityAddTraits(.isHeader)
      }
      // The exact request, never a summary of it: what is allowed is what is shown.
      Text(permission.argumentsJson).font(NessaType.mono).lineSpacing(3)
        .lineLimit(source == nil ? nil : PermissionCardStyle.requestLines).truncationMode(.tail)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, NessaSpacing.sm).padding(.vertical, NessaSpacing.sm)
        .background(
          .white.opacity(0.06),
          in: RoundedRectangle(cornerRadius: PermissionCardStyle.requestRadius, style: .continuous))
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
              .frame(maxWidth: .infinity).frame(height: PermissionCardStyle.buttonHeight)
              .foregroundStyle(primary ? MessagesStyle.background : MessagesStyle.foreground)
              .background(primary ? MessagesStyle.foreground : NessaColor.muted, in: Capsule())
          }
          .buttonStyle(.nessaPress)
        }
      }
      .padding(.top, NessaSpacing.xxs)
    }
    .padding(.horizontal, PermissionCardStyle.inset)
    .padding(.top, PermissionCardStyle.inset + NessaSpacing.xxs)
    .padding(.bottom, PermissionCardStyle.inset)
    .background(MessagesStyle.incoming, in: card)
    .overlay(card.strokeBorder(NessaColor.hairline, lineWidth: 1))
  }
}

extension PermissionCard {
  /// Refusals first, then what lets the agent go on, so going on is always on the same side.
  var ordered: [NessaPermission.Option] {
    permission.options.filter { $0.effect != "allow" }
      + permission.options.filter { $0.effect == "allow" }
  }
  /// The narrowest allowing answer is the bright one: the first the agent offered.
  var brightest: NessaPermission.Option? { permission.options.first { $0.effect == "allow" } }
}

private enum PermissionCardStyle {
  static let radius: CGFloat = 26
  static let inset: CGFloat = 18
  static let gap: CGFloat = 14
  static let requestRadius: CGFloat = 12
  static let requestLines = 4
  static let buttonHeight: CGFloat = 46
}
