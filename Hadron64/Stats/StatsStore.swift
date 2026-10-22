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
