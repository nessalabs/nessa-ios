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
      Color(hue: hue(first), saturation: 0.16, brightness: 0.86),
      Color(hue: hue(first + 1), saturation: 0.24, brightness: 0.74)
    )
    blooms = (0..<3).map { index in
      Bloom(
        center: CGPoint(x: random.next(in: 0.1...0.9), y: random.next(in: 0.15...0.95)),
        radius: CGFloat(random.next(in: 0.28...0.46)),
        color: Color(
          hue: hue(first + 2 + index), saturation: random.next(in: 0.26...0.4),
          brightness: random.next(in: 0.78...0.9)
        ).opacity(0.75))
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

/// A fine dithered grain in the foreground ink, densest along the top edge and thinning to
/// nothing below. Each point is a single scattered pixel-sized square with a fixed random
/// threshold, so it reads as film grain rather than a halftone grid. Monochrome on purpose.
/// It is one path drawn once, so it costs nothing while the screen scrolls.
public struct NessaDither: View {
  private let strength: Double
  public init(strength: Double = NessaDither.defaultStrength) { self.strength = strength }
  public static let defaultStrength: Double = 0.1
  private static let cell: CGFloat = 1
  private static let point: CGFloat = 0.67
  /// The densest the grain gets, so even its source reads as grain rather than a fill.
  private static let peak: Double = 0.55
  public var body: some View {
    Canvas { context, size in
      let columns = Int((size.width / Self.cell).rounded(.up))
      let rows = Int((size.height / Self.cell).rounded(.up))
      var path = Path()
      for row in 0..<rows {
        let reach = 1 - Double(row) / Double(max(rows, 1))
        // Eased so the grain thins gradually instead of ending on a visible line.
        let density = Self.peak * reach * reach * reach
        for column in 0..<columns where density > Self.threshold(column, row) {
          path.addRect(
            CGRect(
              x: CGFloat(column) * Self.cell, y: CGFloat(row) * Self.cell,
              width: Self.point, height: Self.point))
        }
      }
      context.fill(path, with: .color(NessaColor.foreground.opacity(strength)))
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
  /// A fixed pseudo-random threshold per point, the same on every draw.
  private static func threshold(_ x: Int, _ y: Int) -> Double {
    var h = UInt32(truncatingIfNeeded: x &* 374_761_393 &+ y &* 668_265_263)
    h = (h ^ (h >> 13)) &* 1_274_126_177
    h ^= h >> 16
    return Double(h & 0xFFFF) / 65_535
  }
}
