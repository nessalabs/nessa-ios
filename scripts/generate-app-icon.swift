import AppKit
import Foundation

// Nessa's vector initial, drawn at each required icon size. No inherited artwork.
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("Contents.json"))) as! [String: Any]
for entry in manifest["images"] as! [[String: String]] {
    let points = Double(entry["size"]!.split(separator: "x")[0])!
    let scale = Double(entry["scale"]!.dropLast())!
    let side = Int(points * scale)
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                 bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGradient(starting: NSColor(srgbRed: 0.9, green: 0.12, blue: 0.16, alpha: 1),
               ending: NSColor(srgbRed: 1, green: 0.46, blue: 0.5, alpha: 1))!
        .draw(in: NSBezierPath(rect: NSRect(x: 0, y: 0, width: side, height: side)), angle: 90)
    let font = NSFont(name: "TimesNewRomanPSMT", size: CGFloat(side) * 0.62)!
    let glyph = NSAttributedString(string: "N", attributes: [.font: font, .foregroundColor: NSColor.white])
    let size = glyph.size()
    glyph.draw(at: NSPoint(x: (CGFloat(side) - size.width) / 2, y: (CGFloat(side) - size.height) / 2))
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(entry["filename"]!))
}
