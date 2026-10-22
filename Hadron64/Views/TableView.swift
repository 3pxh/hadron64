import SwiftUI

/// Where everything sits on a play screen. All positions share one coordinate space,
/// so cards can fly between the deck, the board and the collection stack.
///
///   ┌───────────────────────┐
///   │ top bar               │
///   │      [ ]   [ ]        │  board: rows centered, equal gaps
///   │   [ ]   [ ]   [ ]     │  between cards and between rows
///   │      [ ]   [ ]        │
///   │   • • • • • •         │  controls (remainder line / buttons)
///   │ [stack]       [deck]  │  piles
///   └───────────────────────┘
struct TableLayout {
    static let topBarHeight: CGFloat = 56
    static let controlsHeight: CGFloat = 64
    static let pileScale: CGFloat = 0.42

    let size: CGSize
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
        default: stride(from: 0, to: count, by: 3).map { min(3, count - $0) }
        }
    }

    init(size: CGSize, slotCount: Int) {
        self.size = size
        let pad: CGFloat = 16
        let a = CardGeometry.aspect
        let gapRatio: CGFloat = 0.1

        // Size cards for a 3x3 grid (the widest/tallest board) so card size is the same in every mode.
        var w = (size.width - 2 * pad) / (3 + 2 * gapRatio)
        var h = w / a
        let fixed = Self.topBarHeight + Self.controlsHeight + 28
        let available = size.height - fixed
        if 3 * h + 2 * gapRatio * w + Self.pileScale * h > available {
            h = available / (3 + 2 * gapRatio * a + Self.pileScale)
            w = h * a
        }
        cardSize = CGSize(width: w, height: h)
        gap = gapRatio * w

        let pileW = w * Self.pileScale, pileH = h * Self.pileScale
        let pileY = size.height - 10 - pileH / 2
        stackCenter = CGPoint(x: pad + pileW / 2 + 6, y: pileY)
        deckCenter = CGPoint(x: size.width - pad - pileW / 2 - 6, y: pileY)
        controlsCenter = CGPoint(x: size.width / 2, y: pileY - pileH / 2 - 4 - Self.controlsHeight / 2)

        let boardTop = Self.topBarHeight
        let boardBottom = controlsCenter.y - Self.controlsHeight / 2
        let rows = Self.rows(for: slotCount)
        let boardH = CGFloat(rows.count) * h + CGFloat(rows.count - 1) * gap
        let firstY = (boardTop + boardBottom) / 2 - boardH / 2 + h / 2
        var centers: [CGPoint] = []
        for (r, n) in rows.enumerated() {
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
    /// Show how many cards are left in the deck (deck modes only).
    var showsCounts = true
    var onTap: ((Int) -> Void)?

    private enum Place { case slot(Int), stack(Int) }

    private struct Item: Identifiable {
        let card: PlacedCard
        let place: Place
        var id: Int { card.uid }
    }

    private var items: [Item] {
        table.stack.enumerated().map { Item(card: $1, place: .stack($0)) }
            + table.slots.enumerated().compactMap { i, card in card.map { Item(card: $0, place: .slot(i)) } }
    }

    var body: some View {
        ZStack {
            pile(count: table.collectedCount, isDeck: false).position(layout.stackCenter)
            pile(count: table.deck.count, isDeck: true).position(layout.deckCenter)

            ForEach(items) { item in
                cardView(item)
            }
        }
        .frame(width: layout.size.width, height: layout.size.height)
    }

    @ViewBuilder
    private func cardView(_ item: Item) -> some View {
        let number = item.card.number
        switch item.place {
        case .slot(let i):
            let landed = table.isArrived(item.card)
            let lifted = landed && (selected.contains(number) || highlighted.contains(number) || marked.contains(number))
            ZStack {
                CardView(number: number)
                CardBackView().opacity(landed ? 0 : 1)
            }
            .frame(width: layout.cardSize.width, height: layout.cardSize.height)
            .contentShape(CardShape())
            .onTapGesture { if landed { onTap?(number) } }
            .overlay(CardShape().strokeBorder(Palette.ink, lineWidth: selected.contains(number) && landed ? 3 : 0))
            .overlay(CardShape().inset(by: -5).strokeBorder(Palette.yellow, lineWidth: marked.contains(number) && landed ? 4 : 0))
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
            .shadow(color: .black.opacity(lifted ? 0.22 : 0.08), radius: lifted ? 10 : 3, y: lifted ? 6 : 1.5)
            .scaleEffect(landed ? (lifted ? 1.04 : 1) : TableLayout.pileScale)
            .offset(y: lifted ? -layout.cardSize.height * 0.04 : 0)
            .animation(.spring(duration: 0.22, bounce: 0.3), value: lifted)
            .position(landed ? layout.slotCenters[i] : layout.deckCenter)
            .zIndex(landed ? 50 : 60)
            .allowsHitTesting(landed && onTap != nil)
        case .stack(let depth):
            // A little deterministic jitter makes the stack look hand-made.
            let jitter = Double((item.card.uid * 7919) % 13) - 6
            CardView(number: number)
                .frame(width: layout.cardSize.width, height: layout.cardSize.height)
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                .scaleEffect(TableLayout.pileScale)
                .rotationEffect(.degrees(jitter))
                .position(layout.stackCenter)
                .zIndex(100 + Double(depth))
                .allowsHitTesting(false)
        }
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
                    .font(.rounded(15).monospacedDigit())
                    .foregroundStyle(Palette.muted)
                    .fixedSize()
                    .offset(x: isDeck ? -size.width * 0.5 - 14 : size.width * 0.5 + 14)
                    .contentTransition(.numericText())
                    .animation(.default, value: count)
            }
        }
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
