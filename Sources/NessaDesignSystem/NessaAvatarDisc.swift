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

/// An ordered (Bayer 4×4) dither in the foreground ink: a grain of square points, dense at its
/// source and thinning to nothing. Monochrome on purpose, it gives a ground texture without colour.
/// It is one path drawn once, so it costs nothing while the screen scrolls.
public struct NessaDither: View {
  public enum Falloff: Sendable {
    /// Densest along the top edge, gone by the bottom.
    case down
    /// Densest at the centre, gone by the edge of the inscribed circle.
    case radial
  }
  private let falloff: Falloff
  private let strength: Double
  public init(_ falloff: Falloff, strength: Double = NessaDither.defaultStrength) {
    self.falloff = falloff
    self.strength = strength
  }
  public static let defaultStrength: Double = 0.16
  private static let cell: CGFloat = 3
  private static let point: CGFloat = 1.5
  /// The densest the pattern gets, so even its source reads as grain rather than a fill.
  private static let peak: Double = 0.7
  private static let bayer: [[Double]] = [
    [0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5],
  ]
  public var body: some View {
    Canvas { context, size in
      let columns = Int((size.width / Self.cell).rounded(.up))
      let rows = Int((size.height / Self.cell).rounded(.up))
      let center = CGPoint(x: size.width / 2, y: size.height / 2)
      let radius = max(1, min(size.width, size.height) / 2)
      var path = Path()
      for row in 0..<rows {
        for column in 0..<columns {
          let x = CGFloat(column) * Self.cell
          let y = CGFloat(row) * Self.cell
          let reach: Double
          switch falloff {
          case .down:
            reach = 1 - Double(y / max(size.height, 1))
          case .radial:
            reach = 1 - Double(hypot(x - center.x, y - center.y) / radius)
          }
          guard reach > 0 else { continue }
          // Eased so the grain thins gradually instead of ending on a visible line.
          let density = Self.peak * reach * reach
          let threshold = (Self.bayer[row % 4][column % 4] + 0.5) / 16
          if density > threshold {
            path.addRect(CGRect(x: x, y: y, width: Self.point, height: Self.point))
          }
        }
      }
      context.fill(path, with: .color(NessaColor.foreground.opacity(strength)))
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}
