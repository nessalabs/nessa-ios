import SwiftUI

/// The small lit marks' halftone: black, with dots whose area follows the light, as in print.
/// Specks are left out, so the light's edge feathers instead of stepping. The channel tiles and
/// the profile disc draw with it; the home ground keeps its own, which draws only from where
/// its light starts.
enum NessaHalftone {
  /// `light` gives each cell's centre a strength from 0 to 1.
  static func fill(
    _ context: GraphicsContext, _ size: CGSize, cell: CGFloat, smallestDot: CGFloat, color: Color,
    light: (CGPoint) -> Double
  ) {
    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
    var dots = Path()
    var y: CGFloat = 0
    while y < size.height {
      var x: CGFloat = 0
      while x < size.width {
        let diameter = cell * 0.95 * light(CGPoint(x: x + cell / 2, y: y + cell / 2)).squareRoot()
        if diameter > smallestDot {
          dots.addEllipse(
            in: CGRect(
              x: x + (cell - diameter) / 2, y: y + (cell - diameter) / 2, width: diameter,
              height: diameter))
        }
        x += cell
      }
      y += cell
    }
    context.fill(dots, with: .color(color))
  }
}
