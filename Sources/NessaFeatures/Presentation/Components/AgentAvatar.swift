import NessaDesignSystem
import SwiftUI

/// A chat's painted disc, seeded by the chat's id, so chats with the same agent still each
/// have their own face; its rim lights while the agent works.
struct AgentAvatar: View {
  let seed: String
  let size: CGFloat
  var working = false
  var body: some View {
    NessaAvatarDisc(seed: seed, size: size)
      .nessaRim(active: working, in: Circle())
  }
}
