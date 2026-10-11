import NessaDesignSystem
import SwiftUI

struct AgentAvatar: View {
  let name: String
  let size: CGFloat
  var body: some View {
    Text(String(name.prefix(1)).uppercased())
      .font(
        size >= MessagesStyle.pinnedAvatar ? MessagesStyle.initial : MessagesStyle.avatarInitial
      )
      .foregroundStyle(MessagesStyle.foreground)
      .frame(width: size, height: size)
      .background(
        LinearGradient(
          colors: [MessagesStyle.avatarTop, MessagesStyle.avatarBottom], startPoint: .top,
          endPoint: .bottom), in: Circle()
      )
      .accessibilityHidden(true)
  }
}
