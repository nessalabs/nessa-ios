import NessaDesignSystem
import SwiftUI

/// The agent's painted disc, seeded by its name; its rim lights while the agent works.
struct AgentAvatar: View {
  let name: String
  let size: CGFloat
  var working = false
  var body: some View {
    NessaAvatarDisc(seed: name, size: size)
      .nessaRim(active: working, in: Circle())
  }
}
