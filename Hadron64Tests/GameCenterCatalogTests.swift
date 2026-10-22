import XCTest
@testable import Hadron64

final class GameCenterCatalogTests: XCTestCase {
    typealias Catalog = GameCenterCatalog

    func testIDsAreUnique() {
        let ids = Catalog.leaderboards.map(\.id) + Catalog.achievements.map(\.id)
            + Catalog.challenges.map(\.id) + Catalog.activities.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count)
    }

    func testAchievementPointsFitGameCenterLimits() {
        XCTAssertLessThanOrEqual(Catalog.achievements.map(\.points).reduce(0, +), 1000)
        for a in Catalog.achievements { XCTAssert((1...100).contains(a.points), a.id) }
    }

    func testEveryLeaderboardModeHasOneAllTimeAndOneDailyBoard() {
        for mode in Set(Catalog.leaderboards.map(\.mode)) {
            XCTAssertNotNil(Catalog.leaderboard(for: mode, daily: false), mode.rawValue)
            XCTAssertNotNil(Catalog.leaderboard(for: mode, daily: true), mode.rawValue)
            XCTAssertEqual(Catalog.leaderboards(for: mode).count, 2, mode.rawValue)
            XCTAssertFalse(mode.isTraining, "training stays personal")
        }
    }

    func testChallengesAndActivitiesPointAtRealRecords() {
        let boards = Set(Catalog.leaderboards.map(\.id))
        let achievements = Set(Catalog.achievements.map(\.id))
        for c in Catalog.challenges {
            XCTAssert(boards.contains(c.leaderboardID), c.id)
            XCTAssertFalse(Catalog.leaderboards.first { $0.id == c.leaderboardID }!.daily, "challenges use Classic boards")
        }
        for a in Catalog.activities {
            XCTAssertFalse(a.leaderboardIDs.isEmpty, a.id)
            for id in a.achievementIDs { XCTAssert(achievements.contains(id), "\(a.id) → \(id)") }
            XCTAssertEqual(GameMode(rawValue: a.properties[Catalog.Activity.modeKey]!), a.mode)
        }
    }

    func testScores() {
        let board = Catalog.leaderboard(for: .freePlay, daily: true)!
        XCTAssertEqual(board.score(for: deck(duration: 301.234)), 30123)
        XCTAssertNil(board.score(for: deck(duration: 200, hints: 1)), "hinted decks don't count")
        XCTAssertNil(board.score(for: GameRecord(mode: .freePlay, duration: 90, completed: false, cardsCollected: 20, setsFound: 4)))
        let trial = Catalog.leaderboard(for: .timeTrialHard, daily: false)!
        XCTAssertEqual(trial.score(for: GameRecord(mode: .timeTrialHard, duration: 80, completed: false,
                                                   cardsCollected: 17, setsFound: 4)), 17)
    }

    func testDeckTimeAchievementsIgnoreHintedDecks() {
        let history = Catalog.History(games: [deck(duration: 4 * 60, hints: 2), deck(duration: 6 * 60)], events: [])
        XCTAssertEqual(progress("h64.ach.first_deck", history), 1)
        XCTAssertEqual(progress("h64.ach.deck_7min", history), 1)
        XCTAssertEqual(progress("h64.ach.deck_5min", history), 0)
        XCTAssertEqual(progress("h64.ach.decks_10", history), 0.2, accuracy: 1e-9)
    }

    func testStreakCountsConsecutiveDays() {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now).addingTimeInterval(12 * 3600)
        let days = [0, 1, 2, 4, 5, 6, 7, 8].map { cal.date(byAdding: .day, value: -$0, to: today)! }
        let games = days.map { GameRecord(date: $0, mode: .timeTrialEasy, duration: 60, completed: false, cardsCollected: 3, setsFound: 1) }
        XCTAssertEqual(Catalog.History(games: games, events: []).longestDayStreak, 5)
    }

    private func deck(duration: TimeInterval, hints: Int = 0) -> GameRecord {
        GameRecord(mode: .freePlay, duration: duration, completed: true, cardsCollected: 63, setsFound: 14, hintsUsed: hints)
    }

    private func progress(_ id: String, _ history: Catalog.History) -> Double {
        Catalog.achievements.first { $0.id == id }!.progress(history)
    }
}
