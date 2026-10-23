import XCTest
@testable import Hadron64

/// `Hadron64.gamekit` is what Xcode pushes to App Store Connect; `GameCenterCatalog` is what the app reports
/// against. These keep the two describing the same records.
final class GameKitBundleTests: XCTestCase {
    typealias Catalog = GameCenterCatalog

    private struct Resources: Decodable {
        struct Leaderboard: Decodable {
            let vendorIdentifier: String
            let defaultFormatter: String
            let scoreSortType: String
            let recurrenceRule: String?
            let archived: Bool
        }
        struct Achievement: Decodable {
            let vendorIdentifier: String
            let points: Int
            let showBeforeEarned: Bool
            let archived: Bool
        }
        struct Challenge: Decodable { let vendorIdentifier: String }
        struct Relationship: Decodable { let leaderboardLocalID: String }
        struct Activity: Decodable {
            let vendorIdentifier: String
            let properties: [String: String]
        }
        struct Localization: Decodable { let locale: String }

        let leaderboards: [Leaderboard]
        let achievements: [Achievement]
        let challenges: [Challenge]
        let challengeLeaderboardRelationships: [String: [Relationship]]
        let gameActivities: [Activity]
        let leaderboardLocalizations: [String: [Localization]]
        let achievementLocalizations: [String: [Localization]]
    }

    private static let resources: Resources = {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Hadron64.gamekit/gameCenterResources.json")
        struct File: Decodable { let resources: Resources }
        return try! JSONDecoder().decode(File.self, from: Data(contentsOf: url)).resources
    }()

    private var bundle: Resources { Self.resources }

    func testLeaderboardsMatchCatalog() {
        let live = bundle.leaderboards.filter { !$0.archived }
        XCTAssertEqual(Set(live.map(\.vendorIdentifier)), Set(Catalog.leaderboards.map(\.id)))
        for board in Catalog.leaderboards {
            guard let b = live.first(where: { $0.vendorIdentifier == board.id }) else { continue }
            XCTAssertEqual(b.recurrenceRule != nil, board.daily, board.id)
            if board.mode.isTimeTrial {
                XCTAssertEqual(b.defaultFormatter, "INTEGER", board.id)
                XCTAssertEqual(b.scoreSortType, "DESC", board.id)
            } else {
                XCTAssertEqual(b.defaultFormatter, "ELAPSED_TIME_CENTISECOND", board.id)
                XCTAssertEqual(b.scoreSortType, "ASC", board.id)
            }
            XCTAssertFalse(bundle.leaderboardLocalizations[board.id, default: []].isEmpty, "\(board.id) needs a name")
        }
    }

    func testAchievementsMatchCatalog() {
        let live = bundle.achievements.filter { !$0.archived }
        XCTAssertEqual(Set(live.map(\.vendorIdentifier)), Set(Catalog.achievements.map(\.id)))
        for a in Catalog.achievements {
            guard let b = live.first(where: { $0.vendorIdentifier == a.id }) else { continue }
            XCTAssertEqual(b.points, a.points, a.id)
            XCTAssertEqual(b.showBeforeEarned, !a.hidden, a.id)
            XCTAssertFalse(bundle.achievementLocalizations[a.id, default: []].isEmpty, "\(a.id) needs a name")
        }
    }

    func testChallengesMatchCatalog() {
        XCTAssertEqual(Set(bundle.challenges.map(\.vendorIdentifier)), Set(Catalog.challenges.map(\.id)))
        for c in Catalog.challenges {
            XCTAssertEqual(bundle.challengeLeaderboardRelationships[c.id]?.map(\.leaderboardLocalID), [c.leaderboardID], c.id)
        }
    }

    func testActivitiesMatchCatalog() {
        XCTAssertEqual(Set(bundle.gameActivities.map(\.vendorIdentifier)), Set(Catalog.activities.map(\.id)))
        for a in Catalog.activities {
            XCTAssertEqual(bundle.gameActivities.first { $0.vendorIdentifier == a.id }?.properties, a.properties, a.id)
        }
    }

    func testActivityAssociationsMatchCatalog() throws {
        let associations = try Self.associations()
        for a in Catalog.activities {
            XCTAssertEqual(Set(associations["Leaderboard"]?[a.id] ?? []), Set(a.leaderboardIDs), a.id)
            XCTAssertEqual(Set(associations["Achievement"]?[a.id] ?? []), Set(a.achievementIDs), a.id)
        }
    }

    /// Xcode writes `gameActivityAssociatedResources` as alternating type names and maps:
    /// `["Achievement", {activity: [ids]}, "Leaderboard", {activity: [ids]}]`.
    private static func associations() throws -> [String: [String: [String]]] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Hadron64.gamekit/gameCenterResources.json")
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let flat = (root?["resources"] as? [String: Any])?["gameActivityAssociatedResources"] as? [Any] ?? []
        var result: [String: [String: [String]]] = [:]
        for i in stride(from: 0, to: flat.count - 1, by: 2) {
            if let type = flat[i] as? String, let map = flat[i + 1] as? [String: [String]] { result[type] = map }
        }
        return result
    }
}
