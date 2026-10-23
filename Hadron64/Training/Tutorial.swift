import SwiftUI

/// A wordless, hands-on tutorial. Each step is a small table with one goal: make the remainder line empty.
///
/// 1. Three cards, the hand shows each tap. The player watches dots appear in the hexagon and cancel in pairs,
///    and an arrow carries the eye down to the empty hexagon before the celebration.
/// 2. A random deal from the three-dot deck, so there's less to look at while it sinks in.
///    The hand only appears if the player stalls.
/// 3. Four fixed three-dot cards where one is a decoy: its yellow can't cancel, and the hexagon rings that dot in red.
/// 4. Random four-dot deals. The player is left alone for a minute, then the cards outside a set are crossed out.
///
/// After the first two tables, a page of card sums spells out the rule: dots add, pairs cancel, nothing left is a win.
///
/// It ends by offering four-dot practice or Free Play.
@Observable @MainActor
final class TutorialModel {
    private enum Deal {
        case fixed([Int], mask: Int)
        case random(GameMode)
    }

    private static let deals: [Deal] = [
        .fixed([3, 6, 5], mask: CardMath.fullMask),                   // {Y░ R●} {R● B░} {Y░ B░}
        .random(.simple3),
        .fixed([32, 2, 10, 34], mask: GameMode.simple3.dotMask),      // {B●} {R●} {Y● R●} {R● B●}: 10 is the decoy
        .random(.simple4),
        .random(.simple4),
    ]
    static let stepCount = deals.count

    /// The hand-picked tables, in order.
    static var fixedHands: [[Int]] {
        deals.compactMap { if case .fixed(let cards, _) = $0 { cards } else { nil } }
    }
    /// The step the card sums are shown before.
    static let equationsStep = 2

    let table = Table(slotCount: 3, deck: [])
    private(set) var step = 0
    private(set) var selected: Set<Int> = []
    private(set) var hint: Int?
    /// Cards crossed out by the hint on the last tables: they aren't part of the set.
    private(set) var crossed: Set<Int> = []
    private(set) var celebrating = false
    /// The cards of the set just made, glowing on the board before they're collected.
    private(set) var found: Set<Int> = []
    private(set) var isDone = false
    private(set) var showingEquations = false
    /// First table only: the last card tapped, where the arrow starts before it moves down to the hexagon.
    private(set) var pointerCard: Int?
    private(set) var pointerArrived = false

    @ObservationIgnored private var hintTask: Task<Void, Never>?

    var parity: Int { CardMath.parity(selected) }

    /// One more tap finishes a set: the odd dots are exactly a card still on the board.
    var isOneAway: Bool {
        parity != 0 && !selected.contains(parity) && table.boardCards.contains(parity)
    }

    /// Odd dots that no card left on the board can clear: the selection can't become a set from here.
    var stuckDots: Int {
        parity & ~table.boardCards.filter { !selected.contains($0) }.reduce(0, |)
    }

    /// Which dots the current table uses.
    var mask: Int {
        switch deal {
        case .fixed(_, let mask): mask
        case .random(let mode): mode.dotMask
        }
    }

    private var deal: Deal { Self.deals[min(step, Self.stepCount - 1)] }

    /// The last tables hint by crossing out unused cards, and only after a long wait.
    private var crossesOut: Bool { step >= Self.stepCount - 2 }

    /// How long the player is left alone before the hand appears. The first table guides every tap; the decoy table
    /// gives the red ring time to do its work.
    private var hintDelay: Double {
        switch step {
        case 0: 0.35
        case 2: 20
        default: crossesOut ? 60 : 6
        }
    }

    func start() { load() }

    private func load() {
        let cards = switch deal {
        case .fixed(let cards, _): cards
        case .random(let mode): Array(CardMath.deck(mask: mode.dotMask).shuffled().prefix(mode.dealSize))
        }
        selected = []
        crossed = []
        let settle = table.replace(with: cards)
        scheduleHint(after: settle + (step == 0 ? 0.3 : hintDelay))
    }

    func toggle(_ card: Int) {
        guard !celebrating else { return }
        if selected.contains(card) { selected.remove(card) } else { selected.insert(card) }
        if !selected.isEmpty && parity == 0 {
            complete(last: card)
        } else if !crossesOut {
            scheduleHint(after: hintDelay)
        }
    }

    func finishEquations() {
        showingEquations = false
        load()
    }

    private func complete(last card: Int) {
        hintTask?.cancel()
        hint = nil
        crossed = []
        celebrating = true
        // The first table holds the selection while the arrow moves, so the empty hexagon is what it lands on.
        let pointing = step == 0
        if pointing { withAnimation(.easeOut(duration: 0.2)) { pointerCard = card } } else { celebrate() }
        Task {
            if pointing {
                await pointDown()
                celebrate()
            }
            try? await Task.sleep(for: .seconds(DeckGame.celebrationTime))
            table.collect(table.boardCards.filter(found.contains), refill: false)
            found = []
            try? await Task.sleep(for: .seconds(1.0))
            celebrating = false
            step += 1
            if step >= Self.stepCount {
                isDone = true
                table.replace(with: [])
            } else if step == Self.equationsStep {
                showingEquations = true
                table.replace(with: [])
            } else {
                load()
            }
        }
    }

    private func celebrate() {
        found = selected
        selected = []
    }

    /// Move the eye from the board to the hexagon, now empty, so the player sees why the set counts.
    private func pointDown() async {
        try? await Task.sleep(for: .seconds(0.35))
        withAnimation(.easeInOut(duration: 0.8)) { pointerArrived = true }
        try? await Task.sleep(for: .seconds(1.2))
        withAnimation(.easeOut(duration: 0.2)) { pointerCard = nil }
        pointerArrived = false
    }

    private func scheduleHint(after delay: Double) {
        hintTask?.cancel()
        if step > 0 { hint = nil }
        hintTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            withAnimation(.spring(duration: 0.4)) {
                if self.crossesOut { self.crossed = self.unusedCards() } else { self.hint = self.nextHint() }
            }
        }
    }

    /// Every card outside the set nearest the current selection.
    private func unusedCards() -> Set<Int> {
        let board = table.boardCards
        guard let target = CardMath.nearestSet(in: board, to: selected) else { return [] }
        return Set(board).subtracting(target)
    }

    /// Point at a wrongly selected card to undo it, otherwise at the next card of the nearest set.
    private func nextHint() -> Int? {
        let board = table.boardCards
        guard let target = CardMath.nearestSet(in: board, to: selected) else { return nil }
        let targetSet = Set(target)
        return board.first { selected.contains($0) && !targetSet.contains($0) }
            ?? board.first { targetSet.contains($0) && !selected.contains($0) }
    }
}

struct TutorialScreen: View {
    /// Start the mode picked at the end of the tutorial.
    var onPlay: (GameMode) -> Void = { _ in }

    @State private var model = TutorialModel()
    @State private var unlock: SupportView.Reason?
    @Environment(Supporter.self) private var supporter
    @AppStorage("hasSeenTutorial") private var hasSeenTutorial = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.uiScale) private var s

    var body: some View {
        GeometryReader { geo in
            let layout = TableLayout(size: geo.size, slotCount: model.table.slots.count, scale: s)
            ZStack {
                CardTableView(table: model.table, layout: layout, selected: model.selected,
                              crossed: model.crossed, celebrating: model.found,
                              showsCounts: false, showsStack: false) {
                    model.toggle($0)
                }
                if !model.showingEquations {
                    ParityHex(value: model.parity, mask: model.mask, height: layout.controlsHeight,
                              success: !model.found.isEmpty,
                              guide: .init(active: !model.selected.isEmpty, oneAway: model.isOneAway,
                                           stuck: model.stuckDots))
                        .position(layout.controlsCenter)
                        .transition(.opacity)
                }

                if let hint = model.hint, let index = model.table.slots.firstIndex(where: { $0?.number == hint }) {
                    TapHint(cardSize: layout.cardSize)
                        .position(layout.slotCenters[index])
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                if let card = model.pointerCard, let index = model.table.slots.firstIndex(where: { $0?.number == card }) {
                    let size = layout.cardSize.width * 0.42
                    let goal = CGPoint(x: layout.controlsCenter.x,
                                       y: layout.controlsCenter.y - layout.controlsHeight / 2 - size * 0.6)
                    GoalPointer(size: size)
                        .position(model.pointerArrived ? goal : layout.slotCenters[index])
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                if model.showingEquations {
                    EquationsPage(onContinue: model.finishEquations)
                        .padding(.top, layout.topBarHeight)
                        .transition(.opacity)
                }

                if model.celebrating && model.found.isEmpty && model.pointerCard == nil {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 96 * s, weight: .bold))
                        .symbolRenderingMode(.palette)
                        // Paint the check white: on its own it's a see-through cutout.
                        .foregroundStyle(.white, Palette.ink)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                }

                if model.isDone {
                    finale.transition(.scale(scale: 0.8).combined(with: .opacity))
                }

                topBar
                    .frame(height: layout.topBarHeight)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .background(Palette.paper.ignoresSafeArea())
        .animation(.spring(duration: 0.4, bounce: 0.4), value: model.celebrating)
        .animation(.spring(duration: 0.5), value: model.isDone)
        .animation(.easeInOut(duration: 0.4), value: model.showingEquations)
        .sensoryFeedback(.selection, trigger: model.selected)
        .sensoryFeedback(.success, trigger: model.step)
        .onAppear { model.start() }
        .onDisappear { hasSeenTutorial = true }
        .sheet(item: $unlock) { SupportView(reason: $0) }
        .statusBarHidden()
    }

    private var topBar: some View {
        HStack {
            IconButton(systemName: "xmark") { dismiss() }
            Spacer()
        }
        .padding(.horizontal, 16 * s)
        .overlay {
            HStack(spacing: 8 * s) {
                ForEach(0..<TutorialModel.stepCount, id: \.self) { i in
                    Circle()
                        .fill(i < model.step ? Palette.ink : (i == model.step ? Palette.ink.opacity(0.5) : Palette.faint))
                        .frame(width: (i == model.step ? 12 : 9) * s, height: (i == model.step ? 12 : 9) * s)
                }
            }
            .animation(.spring(duration: 0.3), value: model.step)
        }
    }

    private var finale: some View {
        VStack(spacing: 28 * s) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 88 * s, weight: .semibold))
                .symbolRenderingMode(.palette)
                // Paint the check white: on its own it's a see-through cutout.
                .foregroundStyle(.white, Palette.ink)
                .symbolEffect(.bounce, value: model.isDone)
            VStack(spacing: 14 * s) {
                Button { play(.simple4) } label: {
                    Label("Training · 5 cards", systemImage: "dumbbell.fill")
                }
                .buttonStyle(MenuButtonStyle(filled: true))
                .overlay(alignment: .topTrailing) {
                    if supporter.isLocked(.game(.simple4)) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11 * s, weight: .bold))
                            .foregroundStyle(Palette.paper.opacity(0.7))
                            .padding(10 * s)
                            .allowsHitTesting(false)
                    }
                }
                Button { play(.freePlay) } label: {
                    Label(GameMode.freePlay.title, systemImage: "infinity")
                }
                .buttonStyle(MenuButtonStyle())
            }
            .frame(maxWidth: 320 * s)
            .padding(.horizontal, 24)
        }
    }

    /// Practice counts toward today's free training plays, like starting it from the menu.
    private func play(_ mode: GameMode) {
        let next = Session.game(mode)
        guard supporter.allows(next) else {
            unlock = .dailyLimit
            return
        }
        supporter.recordPlay(next)
        onPlay(mode)
    }
}

/// A downward arrow drawn like the tap hint's hand, but with no ring or bobbing: "look here", not "tap here".
private struct GoalPointer: View {
    let size: CGFloat

    var body: some View {
        Image(systemName: "arrowshape.down.fill")
            .font(.system(size: size))
            .foregroundStyle(Palette.ink)
            .shadow(color: Palette.paper, radius: 0, x: 1.5, y: 1.5)
            .shadow(color: Palette.paper, radius: 0, x: -1.5, y: -1.5)
    }
}

/// Three card sums, each starting from the last one's result: two single dots make a pair, two pairs sharing a dot
/// keep the other two, and a card plus itself is nothing, which is a win. Each sum is built up card by card.
private struct EquationsPage: View {
    let onContinue: () -> Void

    // The first table's dots: {Y░} + {R●} = {Y░ R●}, + {R● B░} = {Y░ B░}, + {Y░ B░} = nothing.
    private static let sums: [(Int, Int)] = [(1, 2), (3, 6), (5, 5)]
    /// Beats per row: the first card, then "+ card", then "= card".
    private static let partsPerRow = 3
    /// After the last row, the check lands on the empty card, then the button appears.
    private static let checkBeat = sums.count * partsPerRow
    private static let buttonBeat = checkBeat + 1

    /// How many beats have been revealed.
    @State private var shown = 0
    @Environment(\.uiScale) private var s

    var body: some View {
        GeometryReader { geo in
            let symbol = 28 * s
            let gap = 10 * s
            let button = 72 * s
            let byWidth = (geo.size.width - 32 - 2 * symbol - 4 * gap) / 3
            let byHeight = (geo.size.height - button - 40 * s - 2 * 24 * s) / 3 * CardGeometry.aspect
            let w = min(byWidth, byHeight, 150 * s)
            VStack(spacing: 24 * s) {
                ForEach(Self.sums.indices, id: \.self) { i in
                    let (a, b) = Self.sums[i]
                    row(i, a, b, cardWidth: w, symbol: symbol, gap: gap)
                }
                Button(action: onContinue) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 26 * s, weight: .bold))
                        .foregroundStyle(Palette.paper)
                        .frame(width: button, height: button)
                        .background(Circle().fill(Palette.ink))
                }
                .buttonStyle(.plain)
                .opacity(isShown(Self.buttonBeat) ? 1 : 0)
                .scaleEffect(isShown(Self.buttonBeat) ? 1 : 0.8)
                .allowsHitTesting(isShown(Self.buttonBeat))
                .padding(.top, 16 * s)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task {
            // A short beat between the parts of a sum; a longer hold once a sum is complete, so it can be read.
            for beat in 0...Self.buttonBeat {
                let startsRow = beat % Self.partsPerRow == 0 && beat < Self.checkBeat
                let pause = beat == 0 ? 0.4 : startsRow || beat == Self.buttonBeat ? 2.4 : 1.1
                try? await Task.sleep(for: .seconds(pause))
                withAnimation(beat == Self.checkBeat ? .spring(duration: 0.5, bounce: 0.5) : .spring(duration: 0.8, bounce: 0.2)) {
                    shown += 1
                }
            }
        }
    }

    private func isShown(_ beat: Int) -> Bool { beat < shown }

    private func row(_ i: Int, _ a: Int, _ b: Int, cardWidth w: CGFloat, symbol: CGFloat, gap: CGFloat) -> some View {
        let first = i * Self.partsPerRow
        return HStack(spacing: gap) {
            card(a, width: w).revealed(isShown(first), lift: 12 * s)
            Group {
                sign("plus", size: symbol)
                card(b, width: w)
            }
            .revealed(isShown(first + 1), lift: 12 * s)
            Group {
                sign("equal", size: symbol)
                card(a ^ b, width: w)
                    .overlay {
                        if a ^ b == 0 && isShown(Self.checkBeat) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: w * 0.5, weight: .bold))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Palette.green)
                                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                                .transition(.scale(scale: 0.3).combined(with: .opacity))
                        }
                    }
            }
            .revealed(isShown(first + 2), lift: 12 * s)
        }
        .fixedCardLayout()
        .accessibilityElement()
        .accessibilityLabel("Card \(a) plus card \(b) equals card \(a ^ b)")
    }

    private func card(_ number: Int, width: CGFloat) -> some View {
        CardView(number: number)
            .frame(width: width, height: width / CardGeometry.aspect)
            .shadow(color: .black.opacity(0.08), radius: 3, y: 1.5)
    }

    private func sign(_ name: String, size: CGFloat) -> some View {
        Image(systemName: name)
            .font(.system(size: size * 0.8, weight: .bold))
            .foregroundStyle(Palette.muted)
            .frame(width: size)
    }
}

private extension View {
    /// Fade and float up into place once `shown`.
    func revealed(_ shown: Bool, lift: CGFloat) -> some View {
        opacity(shown ? 1 : 0).offset(y: shown ? 0 : lift)
    }
}

/// A pulsing ring around the card plus a bobbing finger: "tap here".
private struct TapHint: View {
    let cardSize: CGSize
    @State private var pulse = false

    var body: some View {
        ZStack {
            CardShape()
                .strokeBorder(Palette.ink.opacity(pulse ? 0.15 : 0.6), lineWidth: 3)
                .frame(width: cardSize.width + 14, height: cardSize.height + 14)
                .scaleEffect(pulse ? 1.05 : 1)
            Image(systemName: "hand.point.up.left.fill")
                .font(.system(size: cardSize.width * 0.42))
                .foregroundStyle(Palette.ink)
                .shadow(color: Palette.paper, radius: 0, x: 1.5, y: 1.5)
                .shadow(color: Palette.paper, radius: 0, x: -1.5, y: -1.5)
                .offset(x: cardSize.width * 0.28, y: cardSize.height * (pulse ? 0.28 : 0.36))
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}
