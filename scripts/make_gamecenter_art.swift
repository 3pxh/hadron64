// Renders Game Center artwork in the app icon's style: paper ground, the six-dot hexagon of a card.
// Achievements are 1024×1024 badges, each showing one card (its number below); activities and challenges
// are 3840×2160 banners showing a set from that mode. Opaque RGB PNGs, as Game Center requires.
// Usage: swift scripts/make_gamecenter_art.swift GameCenterArt
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments[1])

func rgb(_ h: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((h >> 16) & 255) / 255, green: CGFloat((h >> 8) & 255) / 255, blue: CGFloat(h & 255) / 255, alpha: a)
}
let paper: UInt32 = 0xF3EFE6
let rows: [UInt32] = [0xDDAA33, 0xBB5566, 0x004488]

/// One card's dots, centered at (cx, cy). `k` scales the icon's card units (R 81, stroke 16).
/// Bit i is column i / 3, row i % 3; missing dots are faint outlines so the hexagon still reads.
func drawCard(_ ctx: CGContext, number: Int, cx: CGFloat, cy: CGFloat, k: CGFloat) {
    let R: CGFloat = 81, line: CGFloat = 16
    let Ro = (R + line / 2) * k
    let hexR = 2 * Ro + Ro * 0.45
    for bit in 0..<6 {
        let col = bit / 3, row = bit % 3
        let side: CGFloat = col == 0 ? -1 : 1
        let x = cx + side * (row == 1 ? hexR : hexR / 2)
        let y = cy + CGFloat(row - 1) * hexR * sqrt(3) / 2
        ctx.saveGState()
        ctx.translateBy(x: x, y: y); ctx.scaleBy(x: k, y: k)
        let disc = CGRect(x: -R, y: -R, width: 2 * R, height: 2 * R)
        if number & (1 << bit) == 0 {
            ctx.setStrokeColor(rgb(0x000000, 0.12)); ctx.setLineWidth(line); ctx.strokeEllipse(in: disc)
            ctx.restoreGState()
            continue
        }
        ctx.setFillColor(rgb(rows[row]))
        if (row + col) % 2 == 1 {
            ctx.fillEllipse(in: disc)
        } else {
            ctx.saveGState()
            ctx.addEllipse(in: disc); ctx.clip()
            ctx.setFillColor(rgb(0xFFFFFF)); ctx.fill(disc)
            ctx.setFillColor(rgb(rows[row]))
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

func render(width: Int, height: Int, to name: String, draw: (CGContext, CGFloat, CGFloat) -> Void) {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(height)); ctx.scaleBy(x: 1, y: -1)
    ctx.setFillColor(rgb(paper)); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    draw(ctx, CGFloat(width), CGFloat(height))
    let url = outDir.appendingPathComponent(name)
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

// Game Center crops achievement badges to a circle, so the card stays inside the middle.
func badge(_ id: String, card: Int) {
    render(width: 1024, height: 1024, to: "achievements/\(id).png") { ctx, w, h in
        drawCard(ctx, number: card, cx: w / 2, cy: h / 2, k: 1.3)
    }
}

/// A set laid out in a row: the cards' numbers XOR to zero.
func banner(_ path: String, set: [Int]) {
    precondition(set.reduce(0, ^) == 0, "\(path) is not a set")
    render(width: 3840, height: 2160, to: path) { ctx, w, h in
        let step = w / CGFloat(set.count + 1)
        let k = min(1.6, 0.75 * step / 614)  // a card is about 614k wide
        for (i, card) in set.enumerated() {
            drawCard(ctx, number: card, cx: step * CGFloat(i + 1), cy: h / 2, k: k)
        }
    }
}

// Each badge's card: more dots for harder achievements, and 63 (every dot) for the hardest ones.
badge("h64.ach.first_deck", card: 1)
badge("h64.ach.deck_10min", card: 10)
badge("h64.ach.deck_7min", card: 7)
badge("h64.ach.deck_5min", card: 47)
badge("h64.ach.deck_3min", card: 63)
badge("h64.ach.decks_10", card: 12)
badge("h64.ach.decks_100", card: 61)
badge("h64.ach.sets_1000", card: 42)
badge("h64.ach.seven_set", card: 21)
badge("h64.ach.tt_easy_63", card: 9)
badge("h64.ach.tt_medium_63", card: 27)
badge("h64.ach.tt_hard_63", card: 63)
badge("h64.ach.streak_7", card: 56)
badge("h64.ach.training_all", card: 38)

// Free Play shows a seven-card set; time trials get shorter sets as they get harder.
let freePlay = [11, 22, 44, 25, 50, 37, 63]
let easy = [3, 12, 48, 63], medium = [5, 18, 23], hard = [33, 30, 63]
for (kind, ids) in [("activities", ["h64.activity.freeplay", "h64.activity.timetrial.easy", "h64.activity.timetrial.medium", "h64.activity.timetrial.hard"]),
                    ("challenges", ["h64.challenge.freeplay", "h64.challenge.timetrial.easy", "h64.challenge.timetrial.medium", "h64.challenge.timetrial.hard"])] {
    for (id, set) in zip(ids, [freePlay, easy, medium, hard]) { banner("\(kind)/\(id).png", set: set) }
}
