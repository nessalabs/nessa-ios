import NessaDesignSystem
import SwiftUI

struct PermissionReview: View {
  let permission: NessaPermission
  let onAnswer: (NessaPermission.Option) -> Void
  var body: some View {
    VStack(alignment: .leading, spacing: NessaSpacing.sm) {
      Label(permission.title, systemImage: "hand.raised").font(MessagesStyle.title)
      Text(permission.toolName).font(MessagesStyle.caption).foregroundStyle(MessagesStyle.secondary)
      Text(permission.argumentsJson).font(NessaType.mono).textSelection(.enabled)
      ForEach(permission.options) { option in
        Button(option.label) { onAnswer(option) }.foregroundStyle(MessagesStyle.outgoing)
      }
    }.padding(NessaSpacing.md).frame(maxWidth: .infinity, alignment: .leading)
      .background(MessagesStyle.incoming, in: RoundedRectangle(cornerRadius: NessaRadius.xl))
  }
}
