import SwiftUI

/// Shared bookkeeping for the endless drills: timing each round and a running tally.
@Observable @MainActor
class Drill {
    let mode: GameMode
    let table = Table(slotCount: 7, deck: [])
    let clock = GameClock()
    private(set) var solved = 0
    private(set) var totalTime: TimeInterval = 0
    /// True between a correct answer and the next deal; input is ignored.
    private(set) var isResolving = false

    @ObservationIgnored private var roundStart: TimeInterval = 0
    @ObservationIgnored var onFind: ((FindEvent) -> Void)?

    init(mode: GameMode) { self.mode = mode }

    var averageTime: TimeInterval? { solved > 0 ? totalTime / Double(solved) : nil }

    func start() {
        clock.start()
        nextRound()
    }

    func pause() { clock.pause() }
    func resume() { clock.start() }

    /// Override to choose the next hand; call `lay(_:)` with it.
    func nextRound() {}

    func lay(_ cards: [Int]) {
        roundStart = clock.current + table.replace(with: cards)
        isResolving = false
    }

    /// Collect some cards and deal replacements from the deck, starting a new round.
    func refill(collecting cards: [Int]) {
        roundStart = clock.current + table.collect(cards)
        isResolving = false
    }

    /// Log the round and move on after `pause` seconds (time for the player to see they were right).
    func succeed(cards: [Int], pause: Double) {
        let duration = max(0, clock.current - roundStart)
        solved += 1
        totalTime += duration
        isResolving = true
        onFind?(FindEvent(mode: mode, duration: duration, cards: cards))
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(pause))
            self?.nextRound()
        }
    }
}

/// Seven cards; tap the remainder dots to show which dots appear an odd number of times across all of them.
@Observable @MainActor
final class RemainderDrill: Drill {
    private(set) var answer = 0
    private(set) var guess = 0

    init() { super.init(mode: .remainder) }

    override func nextRound() {
        var rng = SystemRandomNumberGenerator()
        let cards = CardMath.remainderDeal(using: &rng)
        answer = CardMath.parity(cards)
        guess = 0
        lay(cards)
    }

    func toggle(_ dot: Dot) {
        guard !isResolving, clock.isRunning else { return }
        guess ^= dot.bit
        if guess == answer { succeed(cards: table.boardCards, pause: 0.6) }
    }
}

/// Seven cards hiding exactly one set; say how many cards are in it.
@Observable @MainActor
final class SetSizeDrill: Drill {
    private(set) var answerSet: [Int] = []
    private(set) var revealed = false
    private(set) var misses = 0
    private(set) var lastMiss: Int?

    init() { super.init(mode: .setSize) }

    override func nextRound() {
        var rng = SystemRandomNumberGenerator()
        let deal = CardMath.uniqueSetDeal(size: Int.random(in: 3...7), using: &rng)
        answerSet = deal.set
        revealed = false
        lastMiss = nil
        lay(deal.cards)
    }

    func guess(_ size: Int) {
        guard !isResolving, clock.isRunning else { return }
        if size == answerSet.count {
            revealed = true
            succeed(cards: answerSet, pause: 1.1)
        } else {
            misses += 1
            lastMiss = size
        }
    }
}

/// Seven full cards. Lock in a group whose remainder is only yellow, then find a second, different group
/// with the same remainder. Together their dots cancel, so the cards in exactly one group form a set and are
/// collected; cards in both groups cancel themselves out and stay on the table.
@Observable @MainActor
final class RemainderMatchDrill: Drill {
    /// The locked first group, and the group being built.
    private(set) var locked: Set<Int> = []
    private(set) var selected: Set<Int> = []
    private(set) var mismatchPulse = 0

    init() { super.init(mode: .remainderMatch) }

    var lockedRemainder: Int { CardMath.parity(locked) }
    var parity: Int { CardMath.parity(selected) }
    var canLock: Bool { locked.isEmpty && CardMath.isYellowOnlyRemainder(parity) }

    override func nextRound() {
        let board = table.boardCards
        if board.isEmpty {
            lay(Self.solvableDraw(keeping: [], count: 7))
        } else {
            // Collect the cards in exactly one group; the shared ones stay.
            let collected = board.filter { locked.contains($0) != selected.contains($0) }
            let remaining = board.filter { !collected.contains($0) }
            table.restock(Self.solvableDraw(keeping: remaining, count: collected.count))
            refill(collecting: collected)
        }
        locked = []
        selected = []
    }

    func toggle(_ card: Int) {
        guard !isResolving, clock.isRunning else { return }
        if selected.contains(card) { selected.remove(card) } else { selected.insert(card) }
        guard !locked.isEmpty, selected != locked, parity == lockedRemainder else { return }
        let set = table.boardCards.filter { locked.contains($0) != selected.contains($0) }
        succeed(cards: set, pause: 1.2)
    }

    /// Lock the current group, or release the locked one.
    func toggleLock() {
        guard !isResolving, clock.isRunning else { return }
        if !locked.isEmpty {
            locked = []
        } else if canLock {
            locked = selected
            selected = []
        } else {
            mismatchPulse += 1
        }
    }

    /// Random new cards (not already on the table) that leave the table solvable.
    private static func solvableDraw(keeping board: [Int], count: Int) -> [Int] {
        let pool = CardMath.deck().filter { !board.contains($0) }
        while true {
            let draw = Array(pool.shuffled().prefix(count))
            if CardMath.hasYellowMatch(board + draw) { return draw }
        }
    }
}
