import Foundation
import Observation

/// Local history of every find and game, persisted as one JSON file in Application Support.
/// This is the source of truth for the Statistics screen; Game Center only ever receives copies.
@Observable @MainActor
final class StatsStore {
    private(set) var events: [FindEvent] = []
    private(set) var games: [GameRecord] = []
    @ObservationIgnored private let fileURL: URL?

    private struct Archive: Codable {
        var version = 1
        var events: [FindEvent]
        var games: [GameRecord]
    }

    /// Pass `nil` for an in-memory store (previews, tests).
    init(fileURL: URL? = StatsStore.defaultURL) {
        self.fileURL = fileURL
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let archive = try? JSONDecoder.iso.decode(Archive.self, from: data) else { return }
        events = archive.events
        games = archive.games
    }

    nonisolated static var defaultURL: URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("hadron64-stats.json")
    }

    func log(_ event: FindEvent) {
        events.append(event)
        save()
        GameCenterService.shared.syncAchievements()
    }

    /// Records a finished game and reports how it compares with earlier ones.
    @discardableResult
    func log(_ game: GameRecord) -> ResultSummary {
        let previousBest = best(for: game.mode)
        games.append(game)
        save()
        GameCenterService.shared.submit(game)

        let isRecord: Bool
        if game.usedHints {
            isRecord = false
        } else if game.mode.isTimeTrial {
            isRecord = game.cardsCollected > 0 && previousBest.map { game.score > $0 } ?? true
        } else {
            isRecord = game.completed && previousBest.map { game.score < $0 } ?? true
        }
        return ResultSummary(record: game, best: best(for: game.mode), average: average(for: game.mode), isNewRecord: isRecord)
    }

    // MARK: Queries

    func events(for mode: GameMode) -> [FindEvent] { events.filter { $0.mode == mode } }

    /// Games that count toward records: every time trial, but only completed decks otherwise, and never hinted ones.
    func scoredGames(for mode: GameMode) -> [GameRecord] {
        games.filter { $0.mode == mode && ($0.completed || mode.isTimeTrial) && !$0.usedHints }
    }

    func best(for mode: GameMode) -> Double? {
        let scores = scoredGames(for: mode).map(\.score)
        return mode.isTimeTrial ? scores.max() : scores.min()
    }

    func average(for mode: GameMode) -> Double? {
        let scores = scoredGames(for: mode).map(\.score)
        return scores.isEmpty ? nil : scores.reduce(0, +) / Double(scores.count)
    }

    private func save() {
        guard let fileURL else { return }
        do {
            let data = try JSONEncoder.iso.encode(Archive(events: events, games: games))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("StatsStore save failed: \(error)")
        }
    }
}

#if DEBUG
extension StatsStore {
    /// An in-memory store with six weeks of plausible, steadily improving play, for screenshots
    /// (`-debugSeedStats YES`). Seeded, so every run draws the same charts.
    static func demo() -> StatsStore {
        let store = StatsStore(fileURL: nil)
        var rng = SeededGenerator(seed: 64)
        let days = 42
        for day in 0..<days {
            let progress = Double(day) / Double(days - 1)
            let date = Calendar.current.date(byAdding: .day, value: day - days + 1, to: .now)!
            for _ in 0..<Int.random(in: 1...2, using: &rng) {
                // A Free Play deck: find times shrink as the player improves.
                var deck = CardMath.deck().shuffled(using: &rng)
                var board: [Int] = []
                var total: TimeInterval = 0
                var sets = 0
                while !deck.isEmpty || !board.isEmpty {
                    while board.count < 7, let next = deck.popLast() { board.append(next) }
                    guard let set = CardMath.allSets(in: board).randomElement(using: &rng) else { break }
                    let base = 9 + 30 * (1 - progress) + Double(set.count - 3) * 4
                    let duration = base * Double.random(in: 0.45...1.7, using: &rng)
                    total += duration
                    sets += 1
                    store.events.append(FindEvent(date: date.addingTimeInterval(total), mode: .freePlay,
                                                  duration: duration, cards: set, hints: 0))
                    board.removeAll { set.contains($0) }
                }
                store.games.append(GameRecord(date: date.addingTimeInterval(total), mode: .freePlay, duration: total,
                                              completed: true, cardsCollected: 63, setsFound: sets, hintsUsed: 0))
            }
            if day % 3 == 0 {
                let cards = 14 + Int(progress * 18) + Int.random(in: -4...4, using: &rng)
                store.games.append(GameRecord(date: date, mode: .timeTrialMedium, duration: 40 + Double(cards) * 4,
                                              completed: false, cardsCollected: cards, setsFound: cards / 4))
            }
        }
        return store
    }
}

/// SplitMix64, so demo data is the same on every launch.
struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
#endif

private extension JSONEncoder {
    static let iso: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

private extension JSONDecoder {
    static let iso: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
