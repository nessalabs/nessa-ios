import SwiftUI

/// Pairing with a desktop: the camera window the orb is read through, and
/// the motion of what replaces it.
public enum PairingStyle {
  /// The square camera window, sized for an orb held at arm's length.
  public static let window: CGFloat = 280
  public static let windowRadius: CGFloat = 28
  public static let windowRim: CGFloat = 1
  /// A step changing (scanning, pairing, waiting, done): a short crossfade.
  public static let stepAnimation = Animation.easeOut(duration: 0.2)
  /// The code field, wide enough for `ABCD-2345` at the title size.
  public static let codeFont = Font.system(size: 24, weight: .semibold, design: .monospaced)
}
