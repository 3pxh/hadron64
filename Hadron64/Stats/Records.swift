import Foundation

/// One "found it" moment: a set collected, a remainder entered, or a set size guessed.
struct FindEvent: Codable, Identifiable, Hashable {
    var id = UUID()
    var date = Date.now
    var mode: GameMode
    /// Seconds since the cards for this find were on the table (the previous find or the deal).
    var duration: TimeInterval
    /// The cards involved, as their 1...63 numbers: the set's cards, or for Remainder all seven dealt cards.
    var cards: [Int]
    /// Free Play hint level used before this find (0, 1 = size shown, 2 = a card shown). nil in older data.
    var hints: Int? = nil

    var size: Int { cards.count }
}

/// One finished game (deck cleared, or time trial clock ran out).
struct GameRecord: Codable, Identifiable, Hashable {
    var id = UUID()
    var date = Date.now
    var mode: GameMode
    var duration: TimeInterval
    var completed: Bool
    var cardsCollected: Int
    var setsFound: Int
    /// Hint button presses during the game. Hinted games don't count for records or leaderboards.
    var hintsUsed: Int? = nil

    var usedHints: Bool { (hintsUsed ?? 0) > 0 }

    /// Time trials are scored by cards collected (higher is better); everything else by time (lower is better).
    var score: Double { mode.isTimeTrial ? Double(cardsCollected) : duration }
}

/// What the end-of-game screen shows.
struct ResultSummary: Identifiable {
    let id = UUID()
    let record: GameRecord
    let best: Double?
    let average: Double?
    let isNewRecord: Bool
}
