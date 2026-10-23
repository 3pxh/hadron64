import SwiftUI

/// Rules for the deck-based modes: Free Play, Time Trial (endless deck), and the Simple Cards drills.
/// Tap cards to select them; the moment the selection's dots all cancel, the set stays on the board while its
/// matching dots disappear pair by pair, and is then collected.
@Observable @MainActor
final class DeckGame {
    let mode: GameMode
    let table: Table
    let clock = GameClock()

    private(set) var selected: Set<Int> = []
    private(set) var setsFound = 0
    private(set) var bonusTime: TimeInterval = 0
    private(set) var isFinished = false
    /// The set just found, held on the board for `celebrationTime` before it's collected.
    private(set) var celebrating: Set<Int> = []
    /// The dots that have disappeared from each card of the set being celebrated.
    private(set) var cancelled: [Int: Int] = [:]

    /// The pairs of a set disappear one after another over this long, however many there are…
    static let cancelWindow = 0.5
    /// …and then the last pair gets this long to fade before the cards are collected.
    static let celebrationTime = cancelWindow + 0.3

    /// Free Play hints, reset after every find. Level 1 reveals the size of a smallest set on the
    /// board; level 2 reveals one card: a member for sets of 3–4, a non-member for 5–6, all of a 7.
    private(set) var hintLevel = 0
    private(set) var hintSet: [Int] = []
    private(set) var hintIncluded: Set<Int> = []
    private(set) var hintExcluded: Set<Int> = []
    private(set) var hintsUsed = 0

    var hintsAllowed: Bool { mode == .freePlay }

    @ObservationIgnored private var roundStart: TimeInterval = 0
    /// The final set has been found and is celebrating; the clock stays stopped.
    @ObservationIgnored private var isClearing = false
    @ObservationIgnored var onFind: ((FindEvent) -> Void)?
    @ObservationIgnored var onFinish: ((GameRecord) -> Void)?

    init(mode: GameMode) {
        self.mode = mode
        let cards = CardMath.deck(mask: mode.dotMask)
        table = Table(slotCount: mode.dealSize, deck: cards.shuffled(), endlessDeck: mode.hasEndlessDeck ? cards : nil)
        clock.onTick = { [weak self] in self?.checkClock() }
    }

    /// Dots that currently appear an odd number of times in the selection.
    var parity: Int { CardMath.parity(selected) }

    var timeRemaining: TimeInterval? {
        mode.timeTrial.map { max(0, $0.start + bonusTime - clock.elapsed) }
    }

    func start() {
        roundStart = table.deal(after: 0.25)
        clock.start()
    }

    func pause() { clock.pause() }
    func resume() { if !isFinished && !isClearing { clock.start() } }

    func toggle(_ card: Int) {
        guard !isFinished, clock.isRunning, celebrating.isEmpty else { return }
        if selected.contains(card) { selected.remove(card) } else { selected.insert(card) }
        if !selected.isEmpty && parity == 0 { collectSelection() }
    }

    private func collectSelection() {
        let now = clock.current
        let cards = table.boardCards.filter(selected.contains)
        let event = FindEvent(mode: mode, duration: max(0, now - roundStart), cards: cards,
                              hints: hintsAllowed ? hintLevel : nil)
        let clearsDeck = !table.isEndless && table.deck.isEmpty && cards.count == table.boardCards.count
        selected = []
        clearHint()
        setsFound += 1
        if let bonus = mode.timeTrial?.bonus { bonusTime += bonus }
        // The last set stops the clock now; the celebration isn't part of the player's time.
        if clearsDeck { isClearing = true; clock.pause() }
        celebrating = Set(cards)
        let pairs = CardMath.cancellingPairs(cards)
        let gap = Self.cancelWindow / Double(max(pairs.count - 1, 1))
        Task { [weak self] in
            for (i, pair) in pairs.enumerated() {
                if i > 0 { try? await Task.sleep(for: .seconds(gap)) }
                self?.cancelled[pair.first, default: 0] |= pair.bit
                self?.cancelled[pair.second, default: 0] |= pair.bit
            }
            try? await Task.sleep(for: .seconds(Self.celebrationTime - Self.cancelWindow))
            guard let self else { return }
            celebrating = []
            onFind?(event)
            roundStart = clock.current + table.collect(cards)
            // Only once the cards are in the stack, which draws them blank, so they don't fill back in on the way.
            cancelled = [:]
            if table.isCleared { finish(completed: true, at: now) }
        }
    }

    func hint() {
        guard hintsAllowed, !isFinished, clock.isRunning, celebrating.isEmpty, hintLevel < 2 else { return }
        let board = table.boardCards
        if hintLevel == 0 {
            let sets = CardMath.allSets(in: board)
            guard let smallest = sets.map(\.count).min() else { return }
            hintSet = sets.filter { $0.count == smallest }.randomElement() ?? []
        } else {
            let members = Set(hintSet)
            let others = board.filter { !members.contains($0) }
            if others.isEmpty {
                hintIncluded = members                      // the whole board is the set
            } else if hintSet.count >= 5 {
                hintExcluded = [others.randomElement()!]    // 5 or 6: rule one card out
            } else {
                hintIncluded = [hintSet.randomElement()!]   // 3 or 4: rule one card in
            }
        }
        hintLevel += 1
        hintsUsed += 1
    }

    private func clearHint() {
        hintLevel = 0
        hintSet = []
        hintIncluded = []
        hintExcluded = []
    }

    private func checkClock() {
        if let remaining = timeRemaining, remaining <= 0 { finish(completed: false) }
    }

    private func finish(completed: Bool, at time: TimeInterval? = nil) {
        guard !isFinished else { return }
        isFinished = true
        clock.pause()
        // A time trial that runs out lasted exactly its allotted time, regardless of tick jitter.
        let duration = completed ? (time ?? clock.current) : (mode.timeTrial.map { $0.start + bonusTime } ?? clock.current)
        // GameCenter: GameRecord flows to StatsStore.log, which forwards it to GameCenterService.submit.
        onFinish?(GameRecord(mode: mode, duration: duration, completed: completed,
                             cardsCollected: table.collectedCount, setsFound: setsFound,
                             hintsUsed: hintsAllowed ? hintsUsed : nil))
    }
}
