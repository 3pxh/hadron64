import SwiftUI

/// Rules for the deck-based modes: Free Play, Time Trial, and the Simple Cards drills.
/// Tap cards to select them; the moment the selection's dots all cancel, it's collected.
@Observable @MainActor
final class DeckGame {
    let mode: GameMode
    let table: Table
    let clock = GameClock()

    private(set) var selected: Set<Int> = []
    private(set) var setsFound = 0
    private(set) var bonusTime: TimeInterval = 0
    private(set) var isFinished = false

    /// Free Play hints, reset after every find. Level 1 reveals the size of a smallest set on the
    /// board; level 2 reveals one card: a member for sets of 3–4, a non-member for 5–6, all of a 7.
    private(set) var hintLevel = 0
    private(set) var hintSet: [Int] = []
    private(set) var hintIncluded: Set<Int> = []
    private(set) var hintExcluded: Set<Int> = []
    private(set) var hintsUsed = 0

    var hintsAllowed: Bool { mode == .freePlay }

    @ObservationIgnored private var roundStart: TimeInterval = 0
    @ObservationIgnored var onFind: ((FindEvent) -> Void)?
    @ObservationIgnored var onFinish: ((GameRecord) -> Void)?

    init(mode: GameMode) {
        self.mode = mode
        table = Table(slotCount: mode.dealSize, deck: CardMath.deck(mask: mode.dotMask).shuffled())
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
    func resume() { if !isFinished { clock.start() } }

    func toggle(_ card: Int) {
        guard !isFinished, clock.isRunning else { return }
        if selected.contains(card) { selected.remove(card) } else { selected.insert(card) }
        if !selected.isEmpty && parity == 0 { collectSelection() }
    }

    private func collectSelection() {
        let now = clock.current
        let cards = table.boardCards.filter(selected.contains)
        onFind?(FindEvent(mode: mode, duration: max(0, now - roundStart), cards: cards,
                          hints: hintsAllowed ? hintLevel : nil))
        selected = []
        clearHint()
        setsFound += 1
        if let bonus = mode.timeTrial?.bonus { bonusTime += bonus }
        roundStart = now + table.collect(cards)
        if table.isCleared { finish(completed: true) }
    }

    func hint() {
        guard hintsAllowed, !isFinished, clock.isRunning, hintLevel < 2 else { return }
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

    private func finish(completed: Bool) {
        guard !isFinished else { return }
        isFinished = true
        clock.pause()
        // A time trial that runs out lasted exactly its allotted time, regardless of tick jitter.
        let duration = completed ? clock.current : (mode.timeTrial.map { $0.start + bonusTime } ?? clock.current)
        // GameCenter: GameRecord flows to StatsStore.log, which forwards it to GameCenterService.submit.
        onFinish?(GameRecord(mode: mode, duration: duration, completed: completed,
                             cardsCollected: table.collectedCount, setsFound: setsFound,
                             hintsUsed: hintsAllowed ? hintsUsed : nil))
    }
}
