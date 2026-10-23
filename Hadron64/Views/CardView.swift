import SwiftUI

enum DotRenderer {
    /// Draws one dot: a filled disc, or white with colored vertical bands clipped to the disc,
    /// then a black outline. All widths scale with the radius.
    static func draw(_ dot: Dot, center c: CGPoint, radius r: CGFloat, in ctx: inout GraphicsContext) {
        let k = r / CardGeometry.dotRadius
        let disc = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        if dot.isSolid {
            ctx.fill(disc, with: .color(dot.color))
        } else {
            // Bands span the inside of the outline; odd indices are colored, so white sits at both edges.
            let inner = r - CardGeometry.strokeWidth * k / 2
            let band = 2 * inner / CGFloat(CardGeometry.stripeBands)
            var stripes = Path()
            for i in stride(from: 1, to: CardGeometry.stripeBands, by: 2) {
                stripes.addRect(CGRect(x: c.x - inner + CGFloat(i) * band, y: c.y - r, width: band, height: 2 * r))
            }
            ctx.fill(disc, with: .color(.white))
            var clipped = ctx
            clipped.clip(to: disc)
            clipped.fill(stripes, with: .color(dot.color))
        }
        ctx.stroke(disc, with: .color(.black), lineWidth: CardGeometry.strokeWidth * k)
    }
}

struct CardShape: InsettableShape {
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: inset, dy: inset)
        return Path(roundedRect: r, cornerRadius: max(0, rect.width * 0.07 - inset), style: .continuous)
    }

    func inset(by amount: CGFloat) -> CardShape {
        CardShape(inset: inset + amount)
    }
}

/// The face of card `number`. Size it with a frame; it draws at the print proportions.
struct CardView: View {
    let number: Int

    var body: some View {
        Canvas { ctx, size in
            let k = size.width / CardGeometry.width
            for dot in Dot.allCases where number & dot.bit != 0 {
                let p = CardGeometry.center(of: dot)
                DotRenderer.draw(dot, center: CGPoint(x: p.x * k, y: p.y * k),
                                 radius: CardGeometry.dotRadius * k, in: &ctx)
            }
        }
        .background(CardShape().fill(number & CardMath.backgroundBit != 0 ? Palette.shade : Palette.card))
        .overlay(CardShape().strokeBorder(Palette.ink.opacity(0.1), lineWidth: 1))
        .accessibilityElement()
        .accessibilityLabel("Card \(number)")
    }
}

/// A card face drawn dot by dot, so single dots can animate: cancelled dots swell and fade like a little burst
/// (and come back if un-cancelled), lit dots grow inside an ink ring, stuck dots inside a red one. A shaded background
/// (Extra Hard) cancels too, fading to plain.
/// Draws like `CardView` otherwise; use that where dots never change.
struct CancellingCardView: View {
    let number: Int
    var cancelled = 0
    var lit = 0
    var stuck = 0

    var body: some View {
        GeometryReader { geo in
            let k = geo.size.width / CardGeometry.width
            // DotView leaves room for the outline around the radius.
            let side = 2 * (CardGeometry.dotRadius + CardGeometry.strokeWidth / 2) * k
            ForEach(Dot.allCases.filter { number & $0.bit != 0 }) { dot in
                let p = CardGeometry.center(of: dot)
                let gone = cancelled & dot.bit != 0
                let isLit = lit & dot.bit != 0
                let isStuck = stuck & dot.bit != 0 && !gone
                DotView(dot: dot)
                    .frame(width: side, height: side)
                    .background {
                        Circle()
                            .strokeBorder(isStuck ? Palette.red : Palette.ink, lineWidth: side * 0.08)
                            .padding(-side * 0.16)
                            .opacity(isLit || isStuck ? 1 : 0)
                    }
                    .scaleEffect(gone ? 1.6 : isLit || isStuck ? 1.15 : 1)
                    .opacity(gone ? 0 : 1)
                    .position(x: p.x * k, y: p.y * k)
            }
        }
        .background {
            CardShape().fill(Palette.shade)
                .opacity(number & ~cancelled & CardMath.backgroundBit != 0 ? 1 : 0)
                .background(CardShape().fill(Palette.card))
        }
        .overlay(CardShape().strokeBorder(Palette.ink.opacity(0.1), lineWidth: 1))
        .animation(.easeOut(duration: 0.35), value: cancelled)
        .animation(.spring(duration: 0.35), value: lit)
        .animation(.spring(duration: 0.35), value: stuck)
        .accessibilityElement()
        .accessibilityLabel("Card \(number)")
    }
}

struct CardBackView: View {
    var body: some View {
        Canvas { ctx, size in
            let k = size.width / CardGeometry.width
            for dot in Dot.allCases {
                let p = CardGeometry.center(of: dot)
                let r = CardGeometry.dotRadius * k
                let c = CGPoint(x: p.x * k, y: p.y * k)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)),
                         with: .color(Palette.faint))
            }
        }
        .background(CardShape().fill(Palette.card))
        .overlay(CardShape().strokeBorder(Palette.ink.opacity(0.1), lineWidth: 1))
    }
}

/// A single dot, as used in the remainder line.
struct DotView: View {
    let dot: Dot

    var body: some View {
        Canvas { ctx, size in
            let side = min(size.width, size.height)
            // Leave room for the outline, which straddles the radius.
            let r = side / 2 / (1 + CardGeometry.strokeWidth / 2 / CardGeometry.dotRadius)
            DotRenderer.draw(dot, center: CGPoint(x: size.width / 2, y: size.height / 2), radius: r, in: &ctx)
        }
    }
}

#Preview {
    HStack {
        CardView(number: 63).frame(width: 120, height: 120 / CardGeometry.aspect)
        CardView(number: 21).frame(width: 120, height: 120 / CardGeometry.aspect)
        CardBackView().frame(width: 120, height: 120 / CardGeometry.aspect)
    }
    .padding()
    .background(Palette.paper)
}
