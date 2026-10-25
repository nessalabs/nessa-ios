import Foundation
import NessaFeatures
import Testing

/// Region values the UI kit's `encodeOrbCode` produces for these codes
/// (nessa_ui `packages/react/src/lib/orb-code.ts`, read with Node). The port
/// must draw and read exactly the kit's layout.
private let kitRegions: [(String, String)] = [
  ("ABCD-2345", "1011111000100110110011010111010011101010101110001011110001000101000110011100110001000010"),
  ("N2FC-LRFH", "1000110100000101010010000101111111010101011111011100001001010010000101010001110101011100"),
  ("AAAA-AAAA", "1011111000000111110000001111100001011111000010111110000001111100000011111000010011111000"),
  ("9999-9999", "1100000111101000001111010000011111100000111111110011011000111010100011110110110110100101"),
  ("77K6-B286", "1100100110100011001100001110010001100010110011001100101010111101010001110110010101011011"),
]

private func bits(_ text: String) -> [UInt8] { text.map { $0 == "1" ? 1 : 0 } }

@Test func orbRegionsMatchTheKit() {
  for (code, expected) in kitRegions {
    #expect(OrbCode.encode(code) == bits(expected), "\(code)")
    #expect(OrbCode.decode(bits(expected)) == code)
  }
}

@Test func orbParsesTheGatewayForms() {
  #expect(OrbCode.parse("abcd2345") == OrbCode.parse("ABCD-2345"))
  #expect(OrbCode.parse("ABCD 2345") != nil)
  #expect(OrbCode.parse("ABCD-234O") == nil)
  #expect(OrbCode.parse("ABCD-234") == nil)
}

@Test func orbCorrectsUpToTwoWrongSymbolsAndRefusesSyncDamage() throws {
  var regions = try #require(OrbCode.encode("N2FC-LRFH"))
  // Payload regions 1 and 30 sit in different symbols.
  regions[1] ^= 1
  regions[30] ^= 1
  #expect(OrbCode.decode(regions) == "N2FC-LRFH")
  var unsynced = try #require(OrbCode.encode("N2FC-LRFH"))
  unsynced[0] ^= 1
  #expect(OrbCode.decode(unsynced) == nil)
}

/// A flat drawing of the orb: a saturated blue disc, dense regions bright,
/// sparse ones dim, with a bright rim and core, turned by `rotation` radians.
/// The kit's reader reads the same drawing (checked with Node).
private func render(_ code: String, size: Int, rotation: Double) throws -> OrbFrame {
  let regions = try #require(OrbCode.encode(code))
  var pixels = [UInt8](repeating: 0, count: size * size * 4)
  let centre = Double(size) / 2
  let radius = Double(size) * 0.42
  let inner2 = 0.22 * 0.22
  let step = (0.9 * 0.9 - inner2) / 4
  for y in 0..<size {
    for x in 0..<size {
      let dx = Double(x) + 0.5 - centre
      let dy = Double(y) + 0.5 - centre
      let r = (dx * dx + dy * dy).squareRoot() / radius
      var level = 0.0
      if r <= 1 {
        if r >= 0.9 || r < 0.22 {
          level = 1
        } else {
          let ring = min(3, Int(((r * r - inner2) / step).rounded(.down)))
          var a = atan2(dx, -dy) - rotation
          a = (a.truncatingRemainder(dividingBy: 2 * .pi) + 2 * .pi)
            .truncatingRemainder(dividingBy: 2 * .pi)
          let sector = min(21, Int((a / (2 * .pi / 22)).rounded(.down)))
          level = regions[ring * 22 + sector] == 1 ? 1 : 0.25
        }
      }
      let at = (y * size + x) * 4
      pixels[at] = UInt8((20 + 30 * level).rounded(.toNearestOrEven))
      pixels[at + 1] = UInt8((60 + 60 * level).rounded(.toNearestOrEven))
      pixels[at + 2] = UInt8((20 + 230 * level).rounded(.toNearestOrEven))
      pixels[at + 3] = 255
    }
  }
  return OrbFrame(pixels: pixels, width: size, height: size)
}

@Test func orbReadsADrawnOrbAtAnyRotationAndSize() throws {
  #expect(OrbCode.read(try render("ABCD-2345", size: 300, rotation: 0)) == "ABCD-2345")
  #expect(OrbCode.read(try render("N2FC-LRFH", size: 500, rotation: 1.1)) == "N2FC-LRFH")
  #expect(OrbCode.read(try render("77K6-B286", size: 900, rotation: 2.5)) == "77K6-B286")
}

@Test func orbReadsNothingInAPlainFrame() {
  let grey = OrbFrame(pixels: [UInt8](repeating: 128, count: 200 * 200 * 4), width: 200, height: 200)
  #expect(OrbCode.read(grey) == nil)
}

@Test func orbScannerWaitsForTwoFramesToAgree() throws {
  var scanner = OrbScanner()
  let frame = try render("N2FC-LRFH", size: 400, rotation: 0.4)
  let empty = OrbFrame(pixels: [UInt8](repeating: 0, count: 64 * 64 * 4), width: 64, height: 64)
  #expect(scanner.read(frame) == nil)
  #expect(scanner.read(empty) == nil)
  #expect(scanner.read(frame) == "N2FC-LRFH")
  scanner.reset()
  #expect(scanner.read(frame) == nil)
}
