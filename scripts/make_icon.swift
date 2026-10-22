// Renders the 1024px app icon: card 63's six dots, arranged on a flat-top hexagon, on paper.
// Usage: swift scripts/make_icon.swift Hadron64/Assets.xcassets/AppIcon.appiconset/icon-1024.png
import AppKit

let out = CommandLine.arguments[1]
let S: CGFloat = 1024
let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
func rgb(_ h: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((h >> 16) & 255) / 255, green: CGFloat((h >> 8) & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: 1)
}
// Flip to top-left origin like the reference.
ctx.translateBy(x: 0, y: S); ctx.scaleBy(x: 1, y: -1)
ctx.setFillColor(rgb(0xF3EFE6)); ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))

// Dot geometry in card units (R 81, stroke 16), scaled 1.5x the old icon's 0.78.
let k: CGFloat = 0.78 * 1.5
let R: CGFloat = 81, line: CGFloat = 16
// Equal gap g between neighbouring dots and between the side dots and the icon edge:
// neighbours sit one circumradius apart (2·Ro + g), and the side extent is circumradius + Ro + g = S/2.
let Ro = (R + line / 2) * k
let g = (S / 2 - 3 * Ro) / 3
let hexR = 2 * Ro + g

let colors: [UInt32] = [0xDDAA33, 0xBB5566, 0x004488]
for col in 0..<2 {
    for row in 0..<3 {
        // Rows 0/2 are the top/bottom edge vertices, row 1 the side vertices.
        let side: CGFloat = col == 0 ? -1 : 1
        let cx = S / 2 + side * (row == 1 ? hexR : hexR / 2)
        let cy = S / 2 + CGFloat(row - 1) * hexR * sqrt(3) / 2
        ctx.saveGState()
        ctx.translateBy(x: cx, y: cy); ctx.scaleBy(x: k, y: k)
        let disc = CGRect(x: -R, y: -R, width: 2 * R, height: 2 * R)
        ctx.setFillColor(rgb(colors[row]))
        if (row + col) % 2 == 1 {
            ctx.fillEllipse(in: disc)
        } else {
            ctx.saveGState()
            ctx.addEllipse(in: disc); ctx.clip()
            ctx.setFillColor(rgb(0xFFFFFF)); ctx.fill(disc)
            ctx.setFillColor(rgb(colors[row]))
            // Four white and three colored bands of equal width across the inside of the outline, white at both edges.
            let band = (2 * R - line) / 7
            for i in stride(from: 1, to: 7, by: 2) {
                ctx.fill(CGRect(x: -R + line / 2 + CGFloat(i) * band, y: -R, width: band, height: 2 * R))
            }
            ctx.restoreGState()
        }
        ctx.setStrokeColor(rgb(0x000000)); ctx.setLineWidth(line); ctx.strokeEllipse(in: disc)
        ctx.restoreGState()
    }
}
let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
