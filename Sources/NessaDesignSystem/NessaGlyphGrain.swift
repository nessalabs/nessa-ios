import SwiftUI

/// A very faint field of monospaced glyphs, the ASCII cousin of the header grain. Each cell
/// shows a glyph from a light-to-heavy ramp when the field's density at that height passes the
/// cell's fixed random threshold, so it is densest at the bottom and gone at the top. The
/// pattern steps one cell sideways every few seconds, paused under Reduce Motion and in the
/// background.
public struct NessaGlyphGrain: View {
  private let lit: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  public init(lit: Bool = false) { self.lit = lit }
  private static let ramp = [".", "·", ":", "+", "░"]
  public var body: some View {
    let still = reduceMotion || scenePhase != .active
    // Paused, the timeline stops ticking altogether, so a still field is drawn once.
    TimelineView(
      .animation(minimumInterval: GlyphStyle.driftStep, paused: still),
      content: { context in
        let drift = still ? 0 : Int(context.date.timeIntervalSinceReferenceDate / GlyphStyle.driftStep)
        field(drift: drift)
      })
    .opacity(lit ? GlyphStyle.litOpacity : GlyphStyle.restOpacity)
    .animation(NessaMotion.standard(NessaMotion.slow), value: lit)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  private func field(drift: Int) -> some View {
    Canvas { context, size in
      let glyphs = Self.ramp.map {
        context.resolve(
          Text($0).font(GlyphStyle.font).foregroundStyle(NessaColor.foreground))
      }
      let cell = GlyphStyle.cell
      let columns = Int((size.width / cell).rounded(.up))
      let rows = Int((size.height / cell).rounded(.up))
      for row in 0..<rows {
        let fromTop = Double(row) / Double(max(rows - 1, 1))
        let density = fromTop * fromTop
        for column in 0..<columns {
          let threshold = Self.threshold(column + drift, row)
          guard density > threshold else { continue }
          let weight = (density - threshold) / max(density, 0.001)
          let index = min(Int(weight * Double(glyphs.count)), glyphs.count - 1)
          context.draw(
            glyphs[index],
            at: CGPoint(
              x: (CGFloat(column) + 0.5) * cell, y: (CGFloat(row) + 0.5) * cell))
        }
      }
    }
  }

  /// A fixed pseudo-random threshold per cell, the same on every draw.
  private static func threshold(_ x: Int, _ y: Int) -> Double {
    var h = UInt32(truncatingIfNeeded: x &* 374_761_393 &+ y &* 668_265_263)
    h = (h ^ (h >> 13)) &* 1_274_126_177
    h ^= h >> 16
    return Double(h & 0xFFFF) / 65_535
  }
}

private enum GlyphStyle {
  static let cell: CGFloat = 6
  static let font = Font.system(size: 6, weight: .medium, design: .monospaced)
  static let restOpacity: Double = 0.06
  /// A shade brighter while the agent works, in step with the composer's rim.
  static let litOpacity: Double = 0.1
  static let driftStep: TimeInterval = 2
}
