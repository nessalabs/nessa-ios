import NessaDesignSystem
import SwiftUI

struct ThreadHeader: View {
  let name: String
  let onBack: () -> Void
  let onDetails: () -> Void
  var isReplyThread = false
  var working = false
  var body: some View {
    ZStack(alignment: isReplyThread ? .topTrailing : .topLeading) {
      HStack {
        if isReplyThread { Spacer() }
        Button(action: onBack) {
          Image(systemName: isReplyThread ? "xmark" : "chevron.left").font(MessagesStyle.icon)
            .frame(width: MessagesStyle.controlHeight, height: MessagesStyle.controlHeight)
            .messagesGlass()
        }.buttonStyle(.nessaPress).accessibilityLabel(isReplyThread ? "Close replies" : "Back to Messages")
        if !isReplyThread { Spacer() }
      }.padding(.horizontal, MessagesStyle.horizontal).zIndex(1)
      Button(action: onDetails) {
        VStack(spacing: NessaSpacing.xxs) {
          AgentAvatar(name: name, size: MessagesStyle.headerAvatar, working: working)
          HStack(spacing: NessaSpacing.xxs) {
            Text(name).font(MessagesStyle.headerName)
            Image(systemName: "chevron.right").font(MessagesStyle.smallIcon).foregroundStyle(
              MessagesStyle.secondary)
          }.padding(.horizontal, NessaSpacing.sm).padding(.vertical, NessaSpacing.xxs)
            .messagesGlass()
        }.frame(maxWidth: .infinity)
      }.buttonStyle(NessaPressStyle(scale: MessagesStyle.headerPressScale)).accessibilityLabel("\(name) agent details")
    }.foregroundStyle(MessagesStyle.foreground).padding(.vertical, NessaSpacing.xxs)
  }
}
