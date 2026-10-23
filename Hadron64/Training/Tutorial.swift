import SwiftUI

/// A wordless, hands-on tutorial. Each step is a small table with one goal: pick cards until every dot on them has
/// cancelled. Picked cards show it directly: matching dots fade out in pairs, and come back when a card is put down.
///
/// 1. Three cards, the hand shows each tap: one dot, a card that cancels it and adds another, then that dot alone.
///    Every tap after the first visibly cancels something.
/// 2. A random deal from the three-dot deck, so there's less to look at while it sinks in.
///    The hand only appears if the player stalls or goes back to a selection they've already tried.
/// 3. Four fixed three-dot cards where one is a decoy: its yellow can't cancel, so once picked it's ringed in red.
/// 4. Random four-dot deals. The player is left alone for a minute, then the cards outside a set are crossed out.
///    The very last one plays like the real game: nothing cancels until the set is complete, then it cancels pair by
///    pair.
///
/// A check answers each set: at once where the dots cancelled as they were picked, after the cancelling otherwise.
///
/// After the first two tables, a page of three-card sums spells out the rule: matching dots cancel in pairs, and a
/// set is three cards with nothing left over. The last sum is a near miss, with a dot left and a red cross.
///
/// It ends by offering four-dot practice or Free Play.
@Observable @MainActor
final class TutorialModel {
    private enum Deal {
        case fixed([Int])
        /// A deal from the deck with these dots, one card more than there are dots, so it always has a set.
        case random(mask: Int)
    }

    private static let solids = Dot.yellowSolid.bit | Dot.redSolid.bit | Dot.blueSolid.bit

    private static let deals: [Deal] = [
        .fixed([1, 3, 2]),              // {Y░} {Y░ R●} {R●}
        .random(mask: solids),
        .fixed([32, 2, 10, 34]),        // {B●} {R●} {Y● R●} {R● B●}: 10 is the decoy
        .random(mask: GameMode.simple4.dotMask),
        .random(mask: GameMode.simple4.dotMask),
    ]
    static let stepCount = deals.count

    /// The hand-picked tables, in order.
    static var fixedHands: [[Int]] {
        deals.compactMap { if case .fixed(let cards) = $0 { cards } else { nil } }
    }
    /// The step the card sums are shown before.
    static let equationsStep = 2

    let table = Table(slotCount: 3, deck: [])
    private(set) var step = 0
    /// The picked cards, in the order they were picked.
    private(set) var picks: [Int] = []
    private(set) var hint: Int?
    /// Cards crossed out by the hint on the last tables: they aren't part of the set.
    private(set) var crossed: Set<Int> = []
    private(set) var celebrating = false
    /// The cards of the set just made, held on the board before they're collected.
    private(set) var found: Set<Int> = []
    /// The check that answers a finished set.
    private(set) var showsCheck = false
    /// The last table, like play, only cancels once the set is complete: these are its dots gone so far.
    private(set) var popped: [Int: Int] = [:]
    private(set) var isDone = false
    private(set) var showingEquations = false

    @ObservationIgnored private var hintTask: Task<Void, Never>?
    /// When the current table was dealt: tapping doesn't push the hint back past this plus `hintDelay`.
    @ObservationIgnored private var dealtAt = Date.now
    /// Selections already tried on this table. Coming back to one means the player is going in circles.
    @ObservationIgnored private var tried: Set<Set<Int>> = []

    var selected: Set<Int> { Set(picks) }
    var parity: Int { CardMath.parity(picks) }

    /// The dots that have cancelled on each card. A found set has cancelled completely, except on the last table,
    /// where it cancels pair by pair once it's found.
    var cancelled: [Int: Int] {
        guard cancelsAsPicked else { return popped }
        return CardMath.cancelled(picks).merging(found.map { ($0, $0) }) { $1 }
    }

    /// Dots left on picked cards that nothing else on the board can cancel: the picks can't become a set from here.
    /// Not on the last table, where nothing cancels until the set is complete.
    var stuck: [Int: Int] {
        guard cancelsAsPicked else { return [:] }
        let stuckDots = parity & ~table.boardCards.filter { !selected.contains($0) }.reduce(0, |)
        let cancelled = cancelled
        return Dictionary(uniqueKeysWithValues: picks.map { ($0, $0 & ~(cancelled[$0] ?? 0) & stuckDots) })
    }

    private var deal: Deal { Self.deals[min(step, Self.stepCount - 1)] }

    /// Every table but the last cancels dots as cards are picked.
    private var cancelsAsPicked: Bool { step < Self.stepCount - 1 }

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
        case .fixed(let cards): cards
        case .random(let mask): Array(CardMath.deck(mask: mask).shuffled().prefix(mask.nonzeroBitCount + 1))
        }
        picks = []
        crossed = []
        tried = []
        let settle = table.replace(with: cards)
        dealtAt = .now.addingTimeInterval(settle)
        scheduleHint(after: settle + (step == 0 ? 0.3 : hintDelay))
    }

    func toggle(_ card: Int) {
        guard !celebrating else { return }
        if let i = picks.firstIndex(of: card) { picks.remove(at: i) } else { picks.append(card) }
        if !picks.isEmpty && parity == 0 {
            complete()
        } else if !crossesOut {
            let isRepeat = !tried.insert(selected).inserted
            scheduleHint(after: isRepeat && !selected.isEmpty ? 0.4 : nextHintDelay)
        }
    }

    /// The idle wait before the hand returns, cut short once the table has gone on longer than `hintDelay`.
    /// Never instant, so a tap isn't immediately answered by the hand.
    private var nextHintDelay: Double {
        let overdue = dealtAt.addingTimeInterval(hintDelay).timeIntervalSinceNow
        return min(hintDelay, max(overdue, 1.5))
    }

    func finishEquations() {
        showingEquations = false
        load()
    }

    private func complete() {
        hintTask?.cancel()
        hint = nil
        crossed = []
        celebrating = true
        let set = table.boardCards.filter(selected.contains)
        found = Set(set)
        picks = []
        Task {
            if cancelsAsPicked {
                // The dots cancelled as the cards were picked, so the check answers the last pick straight away.
                showsCheck = true
            } else {
                // As in play: the set cancels pair by pair, and then it's answered.
                let pairs = CardMath.cancellingPairs(set)
                let gap = DeckGame.cancelWindow / Double(max(pairs.count - 1, 1))
                for (i, pair) in pairs.enumerated() {
                    if i > 0 { try? await Task.sleep(for: .seconds(gap)) }
                    popped[pair.first, default: 0] |= pair.bit
                    popped[pair.second, default: 0] |= pair.bit
                }
                try? await Task.sleep(for: .seconds(0.3))
                showsCheck = true
            }
            try? await Task.sleep(for: .seconds(0.9))
            table.collect(set, refill: false)
            try? await Task.sleep(for: .seconds(0.6))
            // Only now: the collected cards fade out blank.
            found = []
            popped = [:]
            showsCheck = false
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
                              cancelled: model.cancelled, stuck: model.stuck,
                              showsCounts: false, showsStack: false) {
                    model.toggle($0)
                }

                if let hint = model.hint, let index = model.table.slots.firstIndex(where: { $0?.number == hint }) {
                    TapHint(cardSize: layout.cardSize)
                        .position(layout.slotCenters[index])
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                if model.showingEquations {
                    EquationsPage(onContinue: model.finishEquations)
                        .padding(.top, layout.topBarHeight)
                        .transition(.opacity)
                }

                if model.showsCheck {
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
        .animation(.spring(duration: 0.4, bounce: 0.4), value: model.showsCheck)
        .animation(.spring(duration: 0.5), value: model.isDone)
        .animation(.easeInOut(duration: 0.4), value: model.showingEquations)
        .sensoryFeedback(.selection, trigger: model.selected)
        .sensoryFeedback(trigger: model.showsCheck) { _, shown in shown ? .success : nil }
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

/// A few cards at a time, added up. Dots that appear on two of the cards light up together and pop, one pair at a
/// time. The first two sums cancel completely, a set, and get a green check; the last keeps a dot with no partner,
/// which is ringed in red under a red cross.
private struct EquationsPage: View {
    let onContinue: () -> Void

    // {Y░} {Y░ R●} {R●}: the first table again. {Y░} {R●} {B░} {Y░ R● B░}: a set can be more than three cards.
    // {Y░ R●} {R● B░} {Y░}: the blue has no partner.
    private static let examples: [[Int]] = [[1, 3, 2], [1, 2, 4, 7], [3, 6, 1]]

    @State private var example = 0
    /// How many of the current sum's cards are on the page.
    @State private var dealt = 0
    /// The dot whose pair is lit, about to pop.
    @State private var pairing: Dot?
    /// Dots whose pairs have popped.
    @State private var popped = 0
    @State private var showsResult = false
    @State private var showsButton = false
    @Environment(\.uiScale) private var s

    private var cards: [Int] { Self.examples[example] }
    private var leftover: Int { CardMath.parity(cards) }
    /// The card indices on each row: four cards go in two rows of two.
    private var rows: [[Int]] {
        cards.count == 4 ? [[0, 1], [2, 3]] : [Array(cards.indices)]
    }
    /// Dots on exactly two of the cards, in reading order: the pairs that pop.
    private var pairs: [Dot] {
        Dot.readingOrder.filter { dot in cards.filter { $0 & dot.bit != 0 }.count == 2 }
    }

    var body: some View {
        GeometryReader { geo in
            let symbol = 28 * s
            let gap = 10 * s
            let verdict = 88 * s
            let button = 72 * s
            let spacing = 32 * s
            let rowGap = 2 * gap
            let rows = self.rows
            // Later rows open with a plus, so every row keeps a sign's width in front and the cards line up.
            let lead = rows.count > 1
            // Every sum uses the cards of three in a row, and its first row starts where that one row would sit
            // centered. A second row, the check and the button still have to fit below it.
            let below = 2 * spacing + verdict + button
            let byWidth = (geo.size.width - 32 - 2 * (symbol + 2 * gap)) / 3
            let byHeight = (geo.size.height - 2 * spacing - 2 * rowGap - below) / 3 * CardGeometry.aspect
            let w = min(byWidth, byHeight, 150 * s)
            let top = (geo.size.height - w / CardGeometry.aspect - below) / 2
            VStack(spacing: spacing) {
                VStack(spacing: rowGap) {
                    ForEach(rows.indices, id: \.self) { r in
                        HStack(spacing: gap) {
                            if r == 0 && lead { Color.clear.frame(width: symbol, height: 1) }
                            ForEach(rows[r], id: \.self) { i in
                                Group {
                                    if i > 0 { sign("plus", size: symbol) }
                                    card(cards[i], width: w)
                                }
                                .revealed(dealt > i, lift: 12 * s)
                            }
                        }
                    }
                }
                .fixedCardLayout()
                .accessibilityElement()
                .accessibilityLabel(cards.count == 4
                    ? Text("Card \(cards[0]) plus card \(cards[1]) plus card \(cards[2]) plus card \(cards[3])")
                    : Text("Card \(cards[0]) plus card \(cards[1]) plus card \(cards[2])"))
                .accessibilityValue(!showsResult ? Text(verbatim: "") : leftover == 0 ? Text("Set found") : Text("Not a set"))

                Image(systemName: leftover == 0 ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: verdict * 0.9, weight: .bold))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, leftover == 0 ? Palette.green : Palette.red)
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                    .frame(height: verdict)
                    .opacity(showsResult ? 1 : 0)
                    .scaleEffect(showsResult ? 1 : 0.3)
                    .accessibilityHidden(true)

                Button(action: onContinue) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 26 * s, weight: .bold))
                        .foregroundStyle(Palette.paper)
                        .frame(width: button, height: button)
                        .background(Circle().fill(Palette.ink))
                }
                .buttonStyle(.plain)
                .opacity(showsButton ? 1 : 0)
                .scaleEffect(showsButton ? 1 : 0.8)
                .allowsHitTesting(showsButton)
            }
            .padding(.top, top)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .sensoryFeedback(trigger: popped) { old, new in new > old ? .impact(weight: .light) : nil }
        .sensoryFeedback(trigger: showsResult) { _, shown in shown ? (leftover == 0 ? .success : .warning) : nil }
        .task { try? await play() }
    }

    private func play() async throws {
        for i in Self.examples.indices {
            if i > 0 {
                withAnimation(.easeIn(duration: 0.4)) {
                    dealt = 0
                    showsResult = false
                }
                try await pause(0.5)
                example = i
                popped = 0
            }
            for n in 1...Self.examples[i].count {
                try await pause(n == 1 ? 0.4 : 0.7)
                withAnimation(.spring(duration: 0.6, bounce: 0.2)) { dealt = n }
            }
            try await pause(1.0)
            for dot in pairs {
                withAnimation(.spring(duration: 0.35)) { pairing = dot }
                try await pause(0.8)
                withAnimation(.easeOut(duration: 0.35)) {
                    pairing = nil
                    popped |= dot.bit
                }
                try await pause(0.6)
            }
            withAnimation(.spring(duration: 0.5, bounce: 0.5)) { showsResult = true }
            try await pause(2.4)
        }
        withAnimation(.spring(duration: 0.6)) { showsButton = true }
    }

    private func pause(_ seconds: Double) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }

    private func card(_ number: Int, width w: CGFloat) -> some View {
        CancellingCardView(number: number, cancelled: popped, lit: pairing?.bit ?? 0, stuck: showsResult ? leftover : 0)
            .frame(width: w, height: w / CardGeometry.aspect)
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
