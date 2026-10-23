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
