import ImageIO
import NessaDesignSystem
import SwiftUI

/// Fixed-size presentation only; loading and decoding belong to the photo group.
struct PhotoStackCard: View {
  let image: CGImage?
  let loaded: Bool
  let open: () -> Void
  var body: some View {
    Button(action: open) {
      ZStack {
        MessagesStyle.control
        if let image {
          Image(decorative: image, scale: 1).resizable().scaledToFill()
        } else if loaded {
          Label("Photo unavailable on this device", systemImage: "photo")
            .font(MessagesStyle.caption).foregroundStyle(MessagesStyle.secondary)
            .padding(NessaSpacing.sm)
        } else {
          ProgressView().tint(MessagesStyle.foreground)
        }
      }.frame(width: MessagesStyle.photoWidth, height: MessagesStyle.photoStackHeight)
        .clipped().clipShape(RoundedRectangle(cornerRadius: MessagesStyle.photoRadius))
        .contentShape(RoundedRectangle(cornerRadius: MessagesStyle.photoRadius))
    }.buttonStyle(.plain).disabled(image == nil)
      .accessibilityLabel("Photo attachment. Open full screen")
  }
}
