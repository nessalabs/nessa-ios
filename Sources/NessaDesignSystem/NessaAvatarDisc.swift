import SwiftUI

/// A chat's face: the home screen's light in the same halftone as the channel tiles and the
/// profile disc, falling from a few soft sources the seed places, so every chat has its own
/// pattern and the app stays one monochrome ground. The same seed draws the same disc on every
/// launch and device. It is drawn once and holds still: continuous paint work costs frames.
public struct NessaAvatarDisc: View {
  private let paint: NessaAvatarPaint
  private let size: CGFloat
  public init(seed: String, size: CGFloat) {
    self.paint = NessaAvatarPaint(seed: seed)
    self.size = size
  }
  public var body: some View {
    Canvas { context, canvas in
      // The dots keep about the same count across a disc, so a small one is not mush and a
      // large one not coarse.
      let cell = max(AvatarDiscStyle.smallestCell, canvas.width / AvatarDiscStyle.cellsAcross)
      NessaHalftone.fill(
        context, canvas, cell: cell, smallestDot: cell * AvatarDiscStyle.smallestDotShare,
        color: MessagesStyle.channelLight
      ) { p in paint.light(at: CGPoint(x: p.x / canvas.width, y: p.y / canvas.height)) }
    }
    .frame(width: size, height: size)
    .clipShape(Circle())
    .overlay(Circle().strokeBorder(MessagesStyle.litRim, lineWidth: 0.5))
    .drawingGroup()
    .accessibilityHidden(true)
  }
}

enum AvatarDiscStyle {
  static let cellsAcross: CGFloat = 18
  static let smallestCell: CGFloat = 1.6
  static let smallestDotShare: CGFloat = 0.25
  /// The light every cell keeps, so the disc reads whole at its dimmest side.
  static let floor: Double = 0.1
}

/// Where one seed's light comes from. Separate from the view so the choice is plain data.
struct NessaAvatarPaint {
  struct Bloom {
    let center: CGPoint
    let radius: CGFloat
    let strength: Double
  }
  let blooms: [Bloom]

  init(seed: String) {
    var random = SeededRandom(seed: seed)
    blooms = (0..<3).map { _ in
      Bloom(
        center: CGPoint(x: random.next(in: -0.1...1.1), y: random.next(in: -0.1...1.1)),
        radius: CGFloat(random.next(in: 0.45...0.85)),
        strength: random.next(in: 0.55...1))
    }
  }

  /// How lit a point of the unit square is: each bloom fades out over its radius, and they add.
  func light(at p: CGPoint) -> Double {
    let lit = blooms.reduce(0.0) { total, bloom in
      let falloff = max(0, 1 - hypot(p.x - bloom.center.x, p.y - bloom.center.y) / bloom.radius)
      return total + bloom.strength * Double(falloff * falloff)
    }
    return AvatarDiscStyle.floor + (1 - AvatarDiscStyle.floor) * min(1, lit)
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
