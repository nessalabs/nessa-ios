import SwiftUI

/// Nessa's face: a soft painted disc, seeded from a name and the agent hue wheel, the
/// phone's version of the desktop's `RandomAvatar`. The same seed paints the same disc
/// on every launch and device. It is drawn once and holds still: continuous paint work
/// costs frames, which is why the desktop stilled its avatars too.
public struct NessaAvatarDisc: View {
  private let paint: NessaAvatarPaint
  private let size: CGFloat
  public init(seed: String, size: CGFloat) {
    self.paint = NessaAvatarPaint(seed: seed)
    self.size = size
  }
  public var body: some View {
    Canvas { context, canvas in
      let bounds = CGRect(origin: .zero, size: canvas)
      context.fill(
        Path(bounds),
        with: .linearGradient(
          Gradient(colors: [paint.ground.0, paint.ground.1]),
          startPoint: CGPoint(x: bounds.minX, y: bounds.minY),
          endPoint: CGPoint(x: bounds.maxX, y: bounds.maxY)))
      var blooms = context
      blooms.addFilter(.blur(radius: canvas.width * 0.16))
      for bloom in paint.blooms {
        let radius = bloom.radius * canvas.width
        let rect = CGRect(
          x: bloom.center.x * canvas.width - radius, y: bloom.center.y * canvas.height - radius,
          width: radius * 2, height: radius * 2)
        blooms.fill(Path(ellipseIn: rect), with: .color(bloom.color))
      }
      context.fill(
        Path(bounds),
        with: .radialGradient(
          Gradient(colors: [.white.opacity(0.32), .clear]),
          center: CGPoint(x: canvas.width * 0.3, y: canvas.height * 0.22),
          startRadius: 0, endRadius: canvas.width * 0.6))
    }
    .frame(width: size, height: size)
    .clipShape(Circle())
    .overlay(Circle().strokeBorder(NessaColor.hairline, lineWidth: 0.5))
    .drawingGroup()
    .accessibilityHidden(true)
  }
}

/// What to paint for one seed. Separate from the view so the choice is plain data.
struct NessaAvatarPaint {
  struct Bloom {
    let center: CGPoint
    let radius: CGFloat
    let color: Color
  }
  let ground: (Color, Color)
  let blooms: [Bloom]

  init(seed: String) {
    var random = SeededRandom(seed: seed)
    let hues = NessaColor.agentHues
    func hue(_ index: Int) -> Double {
      let base = hues[index % hues.count] + random.next(in: -14.0...14.0)
      return (base + 360).truncatingRemainder(dividingBy: 360) / 360
    }
    let first = Int(random.next(in: 0...Double(hues.count - 1)).rounded())
    ground = (
      Color(hue: hue(first), saturation: 0.30, brightness: 0.97),
      Color(hue: hue(first + 1), saturation: 0.42, brightness: 0.90)
    )
    blooms = (0..<3).map { index in
      Bloom(
        center: CGPoint(x: random.next(in: 0.1...0.9), y: random.next(in: 0.15...0.95)),
        radius: CGFloat(random.next(in: 0.28...0.46)),
        color: Color(
          hue: hue(first + 2 + index), saturation: random.next(in: 0.5...0.72),
          brightness: random.next(in: 0.86...0.98)
        ).opacity(0.85))
    }
  }
}

/// SplitMix64 over a stable FNV-1a hash: `String.hashValue` changes on every launch.
struct SeededRandom {
  private var state: UInt64
  init(seed: String) {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for byte in seed.utf8 {
      hash ^= UInt64(byte)
      hash = hash &* 0x0000_0100_0000_01B3
    }
    state = hash
  }
  mutating func nextBits() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
  mutating func next(in range: ClosedRange<Double>) -> Double {
    let unit = Double(nextBits() >> 11) / Double(1 << 53)
    return range.lowerBound + unit * (range.upperBound - range.lowerBound)
  }
}

/// The brand wash: lavender blooming into warm orange, as light diffusing through fog.
/// For grounds, empty states and brand surfaces, never behind running text.
public struct NessaWash: View {
  private let intensity: Double
  private let feathered: Bool
  /// `feathered` fades the wash out to a circle, for a wash standing on its own.
  public init(intensity: Double = 1, feathered: Bool = false) {
    self.intensity = intensity
    self.feathered = feathered
  }
  public var body: some View {
    if feathered {
      canvas.mask(
        GeometryReader { proxy in
          RadialGradient(
            colors: [.black, .clear], center: .center, startRadius: 0,
            endRadius: min(proxy.size.width, proxy.size.height) / 2)
        })
    } else {
      canvas
    }
  }
  private var canvas: some View {
    Canvas { context, canvas in
      context.addFilter(.blur(radius: max(canvas.width, canvas.height) * 0.14))
      let w = canvas.width
      let h = canvas.height
      let placements: [(CGFloat, CGFloat, CGFloat)] = [
        (0.18, 0.30, 0.55), (0.55, 0.12, 0.50), (0.85, 0.42, 0.48), (0.42, 0.62, 0.42),
      ]
      for (index, placement) in placements.enumerated() {
        let radius = placement.2 * w
        let rect = CGRect(
          x: placement.0 * w - radius, y: placement.1 * h - radius,
          width: radius * 2, height: radius * 2)
        context.fill(
          Path(ellipseIn: rect),
          with: .color(NessaColor.wash[index % NessaColor.wash.count].opacity(0.55 * intensity)))
      }
    }
    .drawingGroup()
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}
