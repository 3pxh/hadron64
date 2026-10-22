// Frames raw simulator captures into App Store screenshots: a caption over the screen, in a plain bezel, on paper.
// Output has the same pixel size as the input, so 6.9" iPhone (1320×2868) and 13" iPad (2064×2752) stay valid.
// Usage: swift scripts/screenshots/frame.swift <raw dir> <out dir> <language>
import AppKit

let args = CommandLine.arguments
let rawDir = URL(fileURLWithPath: args[1]), outDir = URL(fileURLWithPath: args[2]), lang = args[3]
let captionsURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("captions.json")
let json = try! JSONSerialization.jsonObject(with: Data(contentsOf: captionsURL)) as! [String: Any]
let order = json["_order"] as! [String]
let captions = json[lang] as! [String: [String]]
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
}
let paper = color(0xF3EFE6), ink = color(0x1C1C1E), muted = color(0x8A857A)

func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    return NSFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: size) ?? base
}

func text(_ s: String, _ font: NSFont, _ color: NSColor) -> NSAttributedString {
    let p = NSMutableParagraphStyle()
    p.alignment = .center
    p.lineBreakMode = .byWordWrapping
    p.lineHeightMultiple = 1.08
    return NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: p])
}

for name in order {
    guard let shot = NSImage(contentsOf: rawDir.appendingPathComponent("\(name).png")),
          let cg = shot.cgImage(forProposedRect: nil, context: nil, hints: nil),
          let lines = captions[name] else { print("skipping \(name)"); continue }
    let W = CGFloat(cg.width), H = CGFloat(cg.height)
    let isPhone = H / W > 1.6
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: cg.width, pixelsHigh: cg.height, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    paper.setFill()
    NSRect(x: 0, y: 0, width: W, height: H).fill()

    // Caption, measured so long translations wrap rather than clip.
    let textWidth = W * 0.84
    let headline = text(lines[0], rounded(W * (isPhone ? 0.078 : 0.058), .heavy), ink)
    let sub = text(lines[1], rounded(W * (isPhone ? 0.04 : 0.03), .medium), muted)
    let hSize = headline.boundingRect(with: NSSize(width: textWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin])
    let sSize = sub.boundingRect(with: NSSize(width: textWidth, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin])
    // The caption is centered in a fixed band, so the device is the same size on every screenshot.
    let band = H * (isPhone ? 0.2 : 0.17)
    let gap = W * 0.022
    let captionH = ceil(hSize.height) + gap + ceil(sSize.height)
    let hY = H - (band - captionH) / 2 - ceil(hSize.height)
    headline.draw(with: NSRect(x: (W - textWidth) / 2, y: hY, width: textWidth, height: ceil(hSize.height)), options: [.usesLineFragmentOrigin])
    let sY = hY - gap - ceil(sSize.height)
    sub.draw(with: NSRect(x: (W - textWidth) / 2, y: sY, width: textWidth, height: ceil(sSize.height)), options: [.usesLineFragmentOrigin])

    // Device: the capture inside a dark bezel, filling the space below the caption band.
    let bottom = H * 0.035
    let available = H - band - bottom
    let bezel = W * (isPhone ? 0.022 : 0.016)
    let screenH = available - 2 * bezel
    let screenW = screenH * W / H
    let screen = NSRect(x: (W - screenW) / 2, y: bottom + bezel, width: screenW, height: screenH)
    let radius = screenW * (isPhone ? 0.135 : 0.035)
    let body = screen.insetBy(dx: -bezel, dy: -bezel)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.22)
    shadow.shadowBlurRadius = W * 0.03
    shadow.shadowOffset = NSSize(width: 0, height: -W * 0.01)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    color(0x1C1C1E).setFill()
    NSBezierPath(roundedRect: body, xRadius: radius + bezel, yRadius: radius + bezel).fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: screen, xRadius: radius, yRadius: radius).addClip()
    NSGraphicsContext.current?.imageInterpolation = .high
    NSGraphicsContext.current?.cgContext.draw(cg, in: screen)
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    // App Store Connect rejects screenshots with an alpha channel, so flatten to RGB.
    let ctx = CGContext(data: nil, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.draw(rep.cgImage!, in: CGRect(x: 0, y: 0, width: W, height: H))
    let flat = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! flat.representation(using: .png, properties: [:])!.write(to: outDir.appendingPathComponent("\(name).png"))
}
print("framed \(lang)")
