import SwiftUI

/// Nessa's mark: two rings around the one accent dot, drawn in the app's monochrome with
/// the accent kept to its centre.
public struct NessaMark: View {
  private let size: CGFloat
  public init(size: CGFloat) { self.size = size }
  public var body: some View {
    ZStack {
      Circle().stroke(NessaColor.foreground.opacity(0.9), lineWidth: size * 0.0375)
        .padding(size * 0.075)
      Circle().stroke(NessaColor.foreground.opacity(0.55), lineWidth: size * 0.0375)
        .padding(size * 0.225)
      Circle().fill(NessaColor.accent).frame(width: size * 0.225, height: size * 0.225)
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}
