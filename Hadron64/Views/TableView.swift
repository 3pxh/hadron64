import SwiftUI

extension View {
    /// Card faces, the table and dot rows keep their physical left-to-right layout in every language:
    /// a dot's column is part of what it means, so right-to-left locales must not mirror it.
    func fixedCardLayout() -> some View {
        environment(\.layoutDirection, .leftToRight)
    }
}

/// Where everything sits on a play screen. All positions share one coordinate space,
/// so cards can fly between the deck, the board and the collection stack.
///
///   ┌───────────────────────┐
///   │ top bar               │
///   │      [ ]   [ ]        │  board: rows centered, equal gaps
///   │   [ ]   [ ]   [ ]     │  between cards and between rows
///   │      [ ]   [ ]        │
///   │   • • • • • •         │  controls (Remainder drill dots / buttons)
///   │ [stack]       [deck]  │  piles
///   └───────────────────────┘
///
/// On a wide screen (iPad) the controls sit between the piles instead, leaving more room for the board.
struct TableLayout {
    static let pileScale: CGFloat = 0.42

    let size: CGSize
    /// The environment's `uiScale`: the top bar and controls grow with it on iPad.
    let scale: CGFloat
    let topBarHeight: CGFloat
    let controlsHeight: CGFloat
    let cardSize: CGSize
    let gap: CGFloat
    let slotCenters: [CGPoint]
    let deckCenter: CGPoint
    let stackCenter: CGPoint
    let controlsCenter: CGPoint

    var pileSize: CGSize { CGSize(width: cardSize.width * Self.pileScale, height: cardSize.height * Self.pileScale) }

    /// Board row pattern for a given number of slots.
    static func rows(for count: Int) -> [Int] {
        switch count {
        case 1, 2, 3: [count]
        case 4: [2, 2]
        case 5: [2, 1, 2]
        case 6: [2, 2, 2]
        case 7: [2, 3, 2]
        case 8: [3, 2, 3]
        default: stride(from: 0, to: count, by: 3).map { min(3, count - $0) }
        }
    }

    /// `pileInset` pulls the piles in from the sides, to clear things drawn along the edges (multiplayer scores).
    /// `controls` is the height reserved for the controls before scaling. Without `piles` (they aren't drawn), the
    /// controls sit at the bottom and the board takes the room the piles would have used.
    init(size: CGSize, slotCount: Int, scale: CGFloat = 1, pileInset: CGFloat = 0, controls: CGFloat = 80,
         piles: Bool = true) {
        self.size = size
        self.scale = scale
        topBarHeight = 56 * scale
        controlsHeight = controls * scale
        let pad: CGFloat = 16 * scale
        let a = CardGeometry.aspect
        let gapRatio: CGFloat = 0.1

        // Size cards for a 3x3 grid (the widest/tallest board) so card size is the same in every mode.
        var w = (size.width - 2 * pad) / (3 + 2 * gapRatio)
        var h = w / a
        // Room between the piles (and their counts) for the widest controls?
        let controlsBesidePiles = !piles
            || size.width - 2 * (pad + pileInset + Self.pileScale * w + 50 * scale) >= 320 * scale
        let rows = 3 + 2 * gapRatio * a
        if controlsBesidePiles {
            let available = size.height - topBarHeight - 28 * scale
            h = min(h, (available - controlsHeight) / rows)
            if piles { h = min(h, available / (rows + Self.pileScale)) }
        } else {
            let available = size.height - topBarHeight - controlsHeight - 28 * scale
            h = min(h, available / (rows + Self.pileScale))
        }
        w = h * a
        cardSize = CGSize(width: w, height: h)
        gap = gapRatio * w

        let pileW = w * Self.pileScale, pileH = h * Self.pileScale
        let pileY = size.height - 10 * scale - pileH / 2
        stackCenter = CGPoint(x: pad + pileInset + pileW / 2 + 6, y: pileY)
        deckCenter = CGPoint(x: size.width - pad - pileInset - pileW / 2 - 6, y: pileY)
        controlsCenter = controlsBesidePiles
            ? CGPoint(x: size.width / 2, y: size.height - 10 * scale - max(piles ? pileH : 0, controlsHeight) / 2)
            : CGPoint(x: size.width / 2, y: pileY - pileH / 2 - 4 * scale - controlsHeight / 2)

        let boardTop = topBarHeight
        let boardBottom = min(controlsCenter.y - controlsHeight / 2,
                              controlsBesidePiles && piles ? pileY - pileH / 2 : .infinity)
        let pattern = Self.rows(for: slotCount)
        let boardH = CGFloat(pattern.count) * h + CGFloat(pattern.count - 1) * gap
        let firstY = (boardTop + boardBottom) / 2 - boardH / 2 + h / 2
        var centers: [CGPoint] = []
        for (r, n) in pattern.enumerated() {
            let rowW = CGFloat(n) * w + CGFloat(n - 1) * gap
            let firstX = size.width / 2 - rowW / 2 + w / 2
            for i in 0..<n {
                centers.append(CGPoint(x: firstX + CGFloat(i) * (w + gap), y: firstY + CGFloat(r) * (h + gap)))
            }
        }
        slotCenters = centers
    }
}

/// Draws the deck, the collection stack and every card on a `Table`.
struct CardTableView: View {
    let table: Table
    let layout: TableLayout
    var selected: Set<Int> = []
    /// Cards to lift without selecting (hints, revealed answers).
    var highlighted: Set<Int> = []
    /// Cards to ring in yellow (Remainder Matching's locked group, hinted members).
    var marked: Set<Int> = []
    /// Cards to fade and cross out (hinted non-members).
    var crossed: Set<Int> = []
    /// A set that was just found: it stays picked while its dots cancel, then it's collected.
    var celebrating: Set<Int> = []
    /// The dots that have cancelled on each card. Given at all, cards are drawn so their dots can fade, and the
    /// collection stack is blank: everything in it has cancelled.
    var cancelled: [Int: Int]?
    /// Dots to ring in red on each card: left over with nothing on the board to cancel them (tutorial).
    var stuck: [Int: Int] = [:]
    /// Show how many cards are left in the deck (deck modes only).
    var showsCounts = true
    /// Show the collection stack. Without it, collected cards just fade away (tutorial).
    var showsStack = true
    /// Show the deck pile. Without it, cards still fly in from where it would be.
    var showsDeck = true
    var onTap: ((Int) -> Void)?

    private enum Place { case slot(Int), stack(Int) }

    private struct Item: Identifiable {
        let card: PlacedCard
        let place: Place
        var id: Int { card.uid }
    }

    private var items: [Item] {
        (showsStack ? table.stack.enumerated().map { Item(card: $1, place: .stack($0)) } : [])
            + table.slots.enumerated().compactMap { i, card in card.map { Item(card: $0, place: .slot(i)) } }
    }

    var body: some View {
        content.fixedCardLayout()
    }

    @ViewBuilder private var content: some View {
        ZStack {
            if showsStack {
                pile(count: table.collectedCount, isDeck: false).position(layout.stackCenter)
            }
            if showsDeck {
                pile(count: table.deck.count, isDeck: true).position(layout.deckCenter)
            }

            ForEach(items) { item in
                cardView(item)
            }
        }
        .frame(width: layout.size.width, height: layout.size.height)
    }

    /// Board and stack cards are one view, so a collected card visibly travels from its slot down to the stack.
    private func cardView(_ item: Item) -> some View {
        let number = item.card.number
        let k = layout.scale
        let slot: Int? = if case .slot(let i) = item.place { i } else { nil }
        let depth: Int? = if case .stack(let d) = item.place { d } else { nil }
        let landed = slot != nil && table.isArrived(item.card)
        let picked = landed && (selected.contains(number) || celebrating.contains(number))
        let lifted = picked || landed && (highlighted.contains(number) || marked.contains(number))
        // A little deterministic jitter makes the stack look hand-made.
        let jitter = Double((item.card.uid * 7919) % 13) - 6
        return ZStack {
            if let cancelled {
                CancellingCardView(number: number, cancelled: depth != nil ? number : cancelled[number] ?? 0,
                                   stuck: landed ? stuck[number] ?? 0 : 0)
            } else {
                CardView(number: number)
            }
            CardBackView().opacity(landed || depth != nil ? 0 : 1)
        }
        .frame(width: layout.cardSize.width, height: layout.cardSize.height)
        .contentShape(CardShape())
        .onTapGesture { if landed { onTap?(number) } }
        .overlay(CardShape().strokeBorder(Palette.ink, lineWidth: picked ? 3 * k : 0))
        .overlay(CardShape().inset(by: -5 * k).strokeBorder(Palette.yellow, lineWidth: marked.contains(number) && landed ? 4 * k : 0))
        .overlay {
            if crossed.contains(number) && landed {
                ZStack {
                    CardShape().fill(Palette.paper.opacity(0.6))
                    Image(systemName: "xmark")
                        .font(.system(size: layout.cardSize.width * 0.5, weight: .bold))
                        .foregroundStyle(Palette.ink.opacity(0.55))
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .shadow(color: .black.opacity(depth != nil ? 0.12 : lifted ? 0.22 : 0.08),
                radius: depth != nil ? 2 : lifted ? 10 : 3, y: depth != nil ? 1 : lifted ? 6 : 1.5)
        .scaleEffect(landed ? (lifted ? 1.04 : 1) : TableLayout.pileScale)
        .offset(y: lifted ? -layout.cardSize.height * 0.04 : 0)
        .animation(.spring(duration: 0.22, bounce: 0.3), value: lifted)
        .rotationEffect(.degrees(depth != nil ? jitter : 0))
        .position(depth != nil ? layout.stackCenter : landed ? layout.slotCenters[slot!] : layout.deckCenter)
        .zIndex(depth.map { 100 + Double($0) } ?? (landed ? 50 : 60))
        .allowsHitTesting(landed && onTap != nil)
    }

    private func pile(count: Int, isDeck: Bool) -> some View {
        let size = layout.pileSize
        return ZStack {
            if isDeck && count > 0 {
                ForEach(0..<min(3, count), id: \.self) { i in
                    CardBackView()
                        .frame(width: size.width, height: size.height)
                        .offset(x: CGFloat(i) * 1.5, y: CGFloat(-i) * 1.5)
                }
            } else {
                CardShape()
                    .strokeBorder(Palette.faint, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .frame(width: size.width, height: size.height)
            }
        }
        .overlay(alignment: isDeck ? .leading : .trailing) {
            if showsCounts {
                Text("\(count)")
                    .font(.rounded(15 * layout.scale).monospacedDigit())
                    .foregroundStyle(Palette.muted)
                    .fixedSize()
                    .offset(x: isDeck ? -size.width * 0.5 - 14 * layout.scale : size.width * 0.5 + 14 * layout.scale)
                    .contentTransition(.numericText())
                    .animation(.default, value: count)
            }
        }
    }
}

/// The Remainder drill's input: six dots on the app icon's hexagon, each a button. `value` is the dots picked so far,
/// which grow and get a ring. When the answer is right the dots fade and a check comes in.
struct ParityHex: View {
    let value: Int
    var height: CGFloat = 80
    /// The answer was right.
    var success = false
    let onToggle: (Dot) -> Void

    private var remaining: Int { value.nonzeroBitCount }

    // Icon proportions: neighbouring dots sit one circumradius apart, here with room between them so the rings on
    // picked neighbours don't touch.
    private var dotRadius: CGFloat { height / (2 + sqrt(3) * (2 + gapRatio)) }
    private var hexRadius: CGFloat { dotRadius * (2 + gapRatio) }
    private let gapRatio: CGFloat = 1.25

    /// Rows 0/2 are the top/bottom edge vertices, row 1 the side vertices.
    private func offset(of dot: Dot) -> CGSize {
        let side: CGFloat = dot.column == 0 ? -1 : 1
        return CGSize(width: side * (dot.row == 1 ? hexRadius : hexRadius / 2),
                      height: CGFloat(dot.row - 1) * hexRadius * sqrt(3) / 2)
    }

    var body: some View {
        content.fixedCardLayout()
    }

    @ViewBuilder private var content: some View {
        let r = dotRadius
        ZStack {
            ForEach(Dot.allCases) { dot in
                pickable(dot, picked: value & dot.bit != 0, radius: r)
            }
            if success {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: hexRadius * 1.4, weight: .bold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Palette.green)
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
            }
        }
        .frame(width: 2 * (hexRadius + r), height: height)
        // The check lingers so the win can land, then eases out. Innermost, so it wins over `value`.
        .animation(success ? .spring(duration: 0.4, bounce: 0.5) : .easeInOut(duration: 0.4).delay(0.5),
                   value: success)
        .animation(.spring(duration: 0.25, bounce: 0.4), value: value)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Odd dots")
        .accessibilityValue(success ? Text("Set found") : Text("\(remaining)"))
    }

    /// A dot as a button: picked dots grow and get an ink ring. Taps land anywhere within half the way to a neighbour.
    private func pickable(_ dot: Dot, picked: Bool, radius r: CGFloat) -> some View {
        DotView(dot: dot)
            .frame(width: 2 * r, height: 2 * r)
            .background {
                Circle()
                    .strokeBorder(Palette.ink, lineWidth: r * 0.13)
                    .padding(-r * 0.24)
                    .opacity(picked ? 1 : 0)
                    .scaleEffect(picked ? 1 : 0.7)
            }
            .scaleEffect(success ? 0.6 : (picked ? 1.12 : 1))
            .opacity(success ? 0 : 1)
            .frame(width: hexRadius, height: hexRadius)
            .contentShape(Circle())
            .onTapGesture { onToggle(dot) }
            .allowsHitTesting(!success)
            .offset(offset(of: dot))
            .accessibilityElement()
            .accessibilityLabel(dot.accessibilityName)
            .accessibilityAddTraits(picked ? [.isButton, .isSelected] : .isButton)
    }
}

/// The line of six dots under the board showing which dots are odd in the current selection.
/// Even dots show as faint placeholders. When `onToggle` is set, the dots become buttons (Remainder drill).
struct RemainderBar: View {
    let value: Int
    var mask: Int = CardMath.fullMask
    var dotSize: CGFloat = 30
    var onToggle: ((Dot) -> Void)?

    var body: some View {
        content.fixedCardLayout()
    }

    @ViewBuilder private var content: some View {
        HStack(spacing: dotSize * 0.7) {
            ForEach(0..<3) { row in
                let dots = Dot.readingOrder.filter { $0.row == row && mask & $0.bit != 0 }
                if !dots.isEmpty {
                    HStack(spacing: dotSize * 0.25) {
                        ForEach(dots) { dot in slot(dot) }
                    }
                }
            }
        }
        .animation(.spring(duration: 0.25, bounce: 0.4), value: value)
    }

    private func slot(_ dot: Dot) -> some View {
        ZStack {
            Circle()
                .strokeBorder(Palette.faint, style: StrokeStyle(lineWidth: 1.5, dash: onToggle == nil ? [3, 3] : []))
                .background(Circle().fill(onToggle == nil ? .clear : Palette.card))
            if value & dot.bit != 0 {
                DotView(dot: dot).transition(.scale(scale: 0.3).combined(with: .opacity))
            }
        }
        .frame(width: dotSize, height: dotSize)
        .contentShape(Circle().inset(by: -6))
        .onTapGesture { onToggle?(dot) }
        .allowsHitTesting(onToggle != nil)
    }
}
