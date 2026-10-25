import Foundation

/// The desktop's signal orb read back into its pairing code.
///
/// A line-for-line port of the UI kit's `orb-code.ts` (nessa_ui,
/// `packages/react/src/lib/orb-code.ts`), which draws the orb: four rings of
/// 22 sectors, each dense (1) or sparse (0); two sync sectors per ring fix the
/// rotation, and the other 80 carry 8 code symbols and 8 Reed–Solomon parity
/// symbols of 5 bits each. The layout, the whitening mask and the reader's
/// limits must stay exactly the kit's, or a phone reads a different code than
/// the screen drew. `OrbCodeTests` holds vectors produced by the kit.
public enum OrbCode {
  /// The gateway's manual-code alphabet, one symbol per 5 bits.
  public static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
  public static let length = 8
  static let parity = 8
  static let symbols = length + parity
  static let bits = 5
  static let rings = 4
  static let sectors = 22
  static let coreRadius = 0.22
  static let rimRadius = 0.9
  static let syncSectors = [0, 11]
  static let syncValues: [[UInt8]] = [[1, 0], [0, 1], [1, 0], [0, 1]]

  // MARK: GF(32) and Reed–Solomon

  /// Powers of α and their logarithms in GF(32).
  static let field: (exp: [Int], log: [Int]) = {
    var exp = [Int](repeating: 0, count: 62)
    var log = [Int](repeating: 0, count: 32)
    var x = 1
    for i in 0..<31 {
      exp[i] = x
      log[x] = i
      x <<= 1
      if x & 32 != 0 { x ^= 0b100101 }  // x^5 + x^2 + 1
    }
    for i in 31..<62 { exp[i] = exp[i - 31] }
    return (exp: exp, log: log)
  }()

  static func mul(_ a: Int, _ b: Int) -> Int {
    a == 0 || b == 0 ? 0 : field.exp[field.log[a] + field.log[b]]
  }
  static func div(_ a: Int, _ b: Int) -> Int {
    precondition(b != 0, "division by zero in GF(32)")
    return a == 0 ? 0 : field.exp[(field.log[a] + 31 - field.log[b]) % 31]
  }
  static func power(_ exponent: Int) -> Int {
    field.exp[((exponent % 31) + 31) % 31]
  }
  /// Polynomials are arrays of coefficients, highest degree first.
  static func polyMul(_ p: [Int], _ q: [Int]) -> [Int] {
    var out = [Int](repeating: 0, count: p.count + q.count - 1)
    for i in p.indices { for j in q.indices { out[i + j] ^= mul(p[i], q[j]) } }
    return out
  }
  static func polyEval(_ p: [Int], _ x: Int) -> Int {
    var y = p[0]
    for i in 1..<p.count { y = mul(y, x) ^ p[i] }
    return y
  }
  static let generator: [Int] = {
    var g = [1]
    for i in 0..<parity { g = polyMul(g, [1, power(i)]) }
    return g
  }()

  /// The message followed by its parity symbols.
  static func rsEncode(_ message: [Int]) -> [Int] {
    var out = message + [Int](repeating: 0, count: parity)
    for i in message.indices {
      let coefficient = out[i]
      if coefficient == 0 { continue }
      for j in 1..<generator.count { out[i + j] ^= mul(generator[j], coefficient) }
    }
    return message + out[message.count...]
  }

  /// The corrected message and how many symbols were corrected, or nil when
  /// there are more than `limit` errors.
  static func rsCorrect(_ received: [Int], limit: Int = parity / 2) -> (
    message: [Int], corrected: Int
  )? {
    let n = received.count
    let syndromes = (0..<parity).map { polyEval(received, power($0)) }
    if syndromes.allSatisfy({ $0 == 0 }) { return (Array(received[0..<(n - parity)]), 0) }

    // Berlekamp–Massey: the error locator, lowest degree first.
    var locator = [1]
    var previous = [1]
    var length = 0
    var shift = 1
    var last = 1
    for k in 0..<parity {
      var delta = syndromes[k]
      if length >= 1 {
        for i in 1...length { delta ^= mul(i < locator.count ? locator[i] : 0, syndromes[k - i]) }
      }
      if delta == 0 {
        shift += 1
        continue
      }
      let scale = div(delta, last)
      var next = locator
      for i in previous.indices {
        let at = i + shift
        while next.count <= at { next.append(0) }
        next[at] ^= mul(scale, previous[i])
      }
      if 2 * length <= k {
        previous = locator
        length = k + 1 - length
        last = delta
        shift = 1
      } else {
        shift += 1
      }
      locator = next
    }
    while locator.count > 1 && locator[locator.count - 1] == 0 { locator.removeLast() }
    let errors = locator.count - 1
    if errors > limit { return nil }

    // Chien search: position p (from the end) is wrong when the locator vanishes at α^-p.
    var positions: [Int] = []
    for p in 0..<n {
      var value = 0
      for i in locator.indices { value ^= mul(locator[i], power(-p * i)) }
      if value == 0 { positions.append(p) }
    }
    if positions.count != errors { return nil }

    // Forney: the evaluator Ω = S·Λ mod x^parity, lowest degree first.
    var omega = [Int](repeating: 0, count: parity)
    for i in 0..<parity {
      var j = 0
      while j <= i && j < locator.count {
        omega[i] ^= mul(locator[j], syndromes[i - j])
        j += 1
      }
    }
    var corrected = received
    for p in positions {
      var numerator = 0
      for i in omega.indices { numerator ^= mul(omega[i], power(-p * i)) }
      var derivative = 0
      var i = 1
      while i < locator.count {
        derivative ^= mul(locator[i], power(-p * (i - 1)))
        i += 2
      }
      if derivative == 0 { return nil }
      let magnitude = mul(power(p), div(numerator, derivative))
      corrected[n - 1 - p] ^= magnitude
    }
    let check = (0..<parity).map { polyEval(corrected, power($0)) }
    return check.allSatisfy({ $0 == 0 }) ? (Array(corrected[0..<(n - parity)]), errors) : nil
  }

  // MARK: Code ↔ bits

  /// The code's 8 symbols, from "ABCD-2345", "abcd2345" and the like; nil when it is not a code.
  public static func parse(_ code: String) -> [Int]? {
    let bare = code.filter { $0 != "-" && !$0.isWhitespace }.uppercased()
    guard bare.count == length else { return nil }
    var out: [Int] = []
    for character in bare {
      guard let symbol = alphabet.firstIndex(of: character) else { return nil }
      out.append(symbol)
    }
    return out
  }

  /// The code in its display form, two groups of four joined by a hyphen.
  public static func format(_ symbols: [Int]) -> String {
    let text = String(symbols.map { alphabet[$0] })
    return "\(text.prefix(4))-\(text.dropFirst(4))"
  }

  /// A fixed mask over the payload. The kit computes it in JavaScript, where
  /// `>>>` first takes the product modulo 2^32.
  static let whiten: [UInt8] = (0..<(symbols * bits)).map { i in
    UInt8(((UInt64(i) &* 2_654_435_761) & 0xFFFF_FFFF) >> 13 & 1)
  }

  static func region(ring: Int, sector: Int) -> Int { ring * sectors + sector }

  /// Payload sectors in reading order: each ring's sectors, skipping its sync sectors.
  static let payloadRegions: [Int] = {
    var regions: [Int] = []
    for ring in 0..<rings {
      for sector in 0..<sectors where !syncSectors.contains(sector) {
        regions.append(region(ring: ring, sector: sector))
      }
    }
    return regions
  }()

  /// The dense (1) and sparse (0) value of every region for `code`, ring-major.
  public static func encode(_ code: String) -> [UInt8]? {
    guard let parsed = parse(code) else { return nil }
    let word = rsEncode(parsed)
    var regions = [UInt8](repeating: 0, count: rings * sectors)
    for (s, symbol) in word.enumerated() {
      for b in 0..<bits {
        let at = s * bits + b
        regions[payloadRegions[at]] = UInt8((symbol >> (bits - 1 - b)) & 1) ^ whiten[at]
      }
    }
    for (ring, values) in syncValues.enumerated() {
      regions[region(ring: ring, sector: syncSectors[0])] = values[0]
      regions[region(ring: ring, sector: syncSectors[1])] = values[1]
    }
    return regions
  }

  /// The code carried by these region values, or nil when it cannot be recovered.
  public static func decode(_ regions: [UInt8]) -> String? {
    correct(regions)?.code
  }

  static func correct(_ regions: [UInt8], limit: Int = parity / 2) -> (
    code: String, corrected: Int
  )? {
    for ring in 0..<rings {
      if regions[region(ring: ring, sector: syncSectors[0])] != syncValues[ring][0] { return nil }
      if regions[region(ring: ring, sector: syncSectors[1])] != syncValues[ring][1] { return nil }
    }
    var word: [Int] = []
    for s in 0..<symbols {
      var symbol = 0
      for b in 0..<bits {
        let at = s * bits + b
        symbol = (symbol << 1) | Int((regions[payloadRegions[at]] ^ whiten[at]) & 1)
      }
      word.append(symbol)
    }
    guard let result = rsCorrect(word, limit: limit) else { return nil }
    return (format(result.message), result.corrected)
  }

  /// Corrections the frame reader accepts: one freely, two only when at most
  /// one sync sector missed. See the kit for the odds behind them.
  static let readLimit = 2
  static let readLimitUnsynced = 1

  // MARK: Geometry

  /// Inner and outer radius of `ring`, as fractions of the orb's radius. Rings have equal area.
  static func ringBounds(_ ring: Int) -> (Double, Double) {
    let inner2 = coreRadius * coreRadius
    let outer2 = rimRadius * rimRadius
    let step = (outer2 - inner2) / Double(rings)
    return (
      (inner2 + step * Double(ring)).squareRoot(), (inner2 + step * Double(ring + 1)).squareRoot()
    )
  }
}

/// One camera frame or rendered orb: 4 bytes a pixel, row by row. The reader
/// looks only at each pixel's colourfulness (strongest channel minus weakest),
/// so RGBA and BGRA read the same.
public struct OrbFrame: Sendable {
  public let pixels: [UInt8]
  public let width: Int
  public let height: Int
  public let bytesPerRow: Int
  public init(pixels: [UInt8], width: Int, height: Int, bytesPerRow: Int? = nil) {
    self.pixels = pixels
    self.width = width
    self.height = height
    self.bytesPerRow = bytesPerRow ?? width * 4
  }
}

/// One channel of levels: what the kit's reader keeps in all three channels
/// of its ink frame.
struct OrbLevels {
  var values: [Double]
  let width: Int
  let height: Int

  /// JavaScript's `Math.round`: halves round up.
  static func round(_ value: Double) -> Int { Int((value + 0.5).rounded(.down)) }

  func brightness(_ x: Double, _ y: Double) -> Double {
    let px = min(width - 1, max(0, OrbLevels.round(x)))
    let py = min(height - 1, max(0, OrbLevels.round(y)))
    return values[py * width + px]
  }

  /// Mean of a small square patch, so sparse grains read as their region's level.
  func patch(_ x: Double, _ y: Double, half: Int) -> Double {
    var total = 0.0
    var count = 0
    for dy in -half...half {
      for dx in -half...half {
        total += brightness(x + Double(dx), y + Double(dy))
        count += 1
      }
    }
    return total / Double(count)
  }
}

extension OrbCode {
  /// Frames are read at no more than this many pixels on their longer side.
  static let maxSide = 640
  /// Angular bins per sector: the step the rotation search moves in.
  static let bins = 8
  /// The bins of a sector a reader samples, clear of its edges.
  static let innerBins = [2, 3, 4, 5]

  /// The frame as colourfulness, so the saturated orb stands out on any background.
  static func ink(_ frame: OrbFrame) -> OrbLevels {
    var values = [Double](repeating: 0, count: frame.width * frame.height)
    frame.pixels.withUnsafeBufferPointer { data in
      for y in 0..<frame.height {
        let row = y * frame.bytesPerRow
        for x in 0..<frame.width {
          let at = row + x * 4
          let r = data[at]
          let g = data[at + 1]
          let b = data[at + 2]
          values[y * frame.width + x] = Double(max(r, g, b) - min(r, g, b))
        }
      }
    }
    return OrbLevels(values: values, width: frame.width, height: frame.height)
  }

  /// Box-averaged down so the longer side is at most `side`. Levels are kept
  /// as the kit's byte array keeps them: rounded half to even.
  static func shrink(_ frame: OrbLevels, side: Int) -> OrbLevels {
    let factor = Int((Double(max(frame.width, frame.height)) / Double(side)).rounded(.up))
    if factor <= 1 { return frame }
    let width = frame.width / factor
    let height = frame.height / factor
    var out = [Double](repeating: 0, count: width * height)
    for y in 0..<height {
      for x in 0..<width {
        var total = 0.0
        for dy in 0..<factor {
          for dx in 0..<factor {
            total += frame.values[(y * factor + dy) * frame.width + x * factor + dx]
          }
        }
        out[y * width + x] = min(255, max(0, (total / Double(factor * factor)).rounded(.toNearestOrEven)))
      }
    }
    return OrbLevels(values: out, width: width, height: height)
  }

  struct Located {
    let cx: Double
    let cy: Double
    let radius: Double
  }

  /// Where the orb is in the frame: the bright core and rim bound it.
  static func locate(_ frame: OrbLevels) -> Located? {
    let width = frame.width
    let height = frame.height
    let step = max(1, min(width, height) / 240)
    var peak = 0.0
    for y in stride(from: 0, to: height, by: step) {
      for x in stride(from: 0, to: width, by: step) {
        peak = max(peak, frame.brightness(Double(x), Double(y)))
      }
    }
    if peak < 40 { return nil }
    var xs: [Int] = []
    var ys: [Int] = []
    let threshold = peak * 0.3
    for y in stride(from: 0, to: height, by: step) {
      for x in stride(from: 0, to: width, by: step)
      where frame.brightness(Double(x), Double(y)) >= threshold {
        xs.append(x)
        ys.append(y)
      }
    }
    if xs.count < 50 { return nil }
    xs.sort()
    ys.sort()
    func pick(_ values: [Int], _ q: Double) -> Double {
      Double(values[min(values.count - 1, Int((Double(values.count) * q).rounded(.down)))])
    }
    let left = pick(xs, 0.002)
    let right = pick(xs, 0.998)
    let top = pick(ys, 0.002)
    let bottom = pick(ys, 0.998)
    let cx = (left + right) / 2
    let cy = (top + bottom) / 2
    let rough = (right - left + bottom - top) / 4
    // The rim's outer edge is where the mean brightness around the centre
    // falls to half the rim's own peak.
    var profile: [Double] = []
    let limit = Int((rough * 1.4).rounded(.up))
    if limit >= 0 {
      for rho in 0...limit {
        var total = 0.0
        for k in 0..<96 {
          let angle = Double(k) / 96 * Double.pi * 2
          total += frame.brightness(cx + cos(angle) * Double(rho), cy + sin(angle) * Double(rho))
        }
        profile.append(total / 96)
      }
    }
    var peakAt = Int((rough * 0.75).rounded(.down))
    guard peakAt >= 0, peakAt < profile.count else { return nil }
    let peakEnd = min(limit, Int((rough * 1.2).rounded(.up)))
    if peakAt <= peakEnd {
      for rho in peakAt...peakEnd where profile[rho] > profile[peakAt] { peakAt = rho }
    }
    let half = profile[peakAt] / 2
    var edge = peakAt
    while edge < limit && profile[edge + 1] >= half { edge += 1 }
    let above = profile[edge]
    let below = edge + 1 < profile.count ? profile[edge + 1] : above
    let fraction = above == below ? 0 : (above - half) / (above - below)
    return Located(cx: cx, cy: cy, radius: Double(edge) + fraction)
  }

  /// Otsu's split of levels into dim and bright: the threshold, and how far apart the classes sit.
  static func split(_ levels: [Double]) -> (threshold: Double, contrast: Double) {
    let sorted = levels.sorted()
    let total = sorted.reduce(0, +)
    var bestScore = -1.0
    var bestThreshold = sorted[0]
    var bestContrast = 0.0
    var below = 0.0
    for i in 1..<sorted.count {
      below += sorted[i - 1]
      let low = below / Double(i)
      let high = (total - below) / Double(sorted.count - i)
      let score = Double(i * (sorted.count - i)) * (high - low) * (high - low)
      if score > bestScore {
        bestScore = score
        bestThreshold = (sorted[i - 1] + sorted[i]) / 2
        bestContrast = high - low
      }
    }
    return (bestThreshold, bestContrast)
  }

  /// Dense or sparse for every region, each judged against its own ring's neighbourhood.
  static func classify(_ values: [[Double]]) -> [UInt8] {
    let whole = split(values.flatMap { $0 })
    var regions: [UInt8] = []
    for ring in 0..<rings {
      let row = values[ring]
      for sector in 0..<sectors {
        var around: [Double] = []
        for ds in -5...5 { around.append(row[(sector + ds + sectors) % sectors]) }
        let local = split(around)
        let threshold = local.contrast >= whole.contrast * 0.45 ? local.threshold : whole.threshold
        regions.append(row[sector] > threshold ? 1 : 0)
      }
    }
    return regions
  }

  /// The orb sampled once onto a polar grid of sectors × bins per ring.
  static func polarGrid(_ frame: OrbLevels, _ orb: Located) -> [[Double]] {
    let count = sectors * bins
    let half = max(1, OrbLevels.round(orb.radius / 90))
    return (0..<rings).map { ring in
      let (r0, r1) = ringBounds(ring)
      return (0..<count).map { bin in
        let a = (Double(bin) + 0.5) / Double(count) * Double.pi * 2
        var total = 0.0
        for i in 1...4 {
          let r = (r0 + (r1 - r0) * (Double(i) + 0.5) / 6) * orb.radius
          total += frame.patch(orb.cx + sin(a) * r, orb.cy - cos(a) * r, half: half)
        }
        return total / 4
      }
    }
  }

  /// The code read from a polar grid at the best rotation, if any.
  static func readAt(_ grid: [[Double]]) -> (code: String, corrected: Int)? {
    let count = sectors * bins
    var best: (code: String, corrected: Int)?
    for shift in 0..<count {
      let values = grid.map { row in
        (0..<sectors).map { sector in
          var total = 0.0
          for inner in innerBins { total += row[(sector * bins + inner + shift) % count] }
          return total / Double(innerBins.count)
        }
      }
      var regions = classify(values)
      var misses = 0
      for ring in 0..<rings {
        for (which, sector) in syncSectors.enumerated() {
          let at = region(ring: ring, sector: sector)
          let expected = syncValues[ring][which]
          if regions[at] != expected { misses += 1 }
          regions[at] = expected
        }
      }
      if misses > 2 { continue }
      if let read = correct(regions, limit: misses <= 1 ? readLimit : readLimitUnsynced),
        best == nil || read.corrected < best!.corrected
      {
        best = read
      }
      if best?.corrected == 0 { return best }
    }
    return best
  }

  /// Reads the code from one frame, or nil when no orb is found or its code
  /// cannot be recovered. Hold the camera square to the screen. A scanner
  /// should read through `OrbScanner`, which reports only codes two frames agree on.
  public static func read(_ frame: OrbFrame) -> String? {
    let levels = shrink(ink(frame), side: maxSide)
    guard let found = locate(levels) else { return nil }
    var best: (code: String, corrected: Int)?
    for scale in [1, 1.03, 0.97, 1.06, 0.94] {
      let read = readAt(
        polarGrid(levels, Located(cx: found.cx, cy: found.cy, radius: found.radius * scale)))
      if let read, best == nil || read.corrected < best!.corrected { best = read }
      if best?.corrected == 0 { break }
    }
    return best?.code
  }
}

/// Reads a stream of camera frames and reports a code only once two
/// consecutive readable frames agree, so one misread frame never becomes a
/// pairing attempt. Frames with no readable orb in between keep the agreement.
public struct OrbScanner: Sendable {
  private var last: String?
  public init() {}
  public mutating func read(_ frame: OrbFrame) -> String? {
    guard let code = OrbCode.read(frame) else { return nil }
    defer { last = code }
    return code == last ? code : nil
  }
  public mutating func reset() { last = nil }
}
