import GameKit
import UIKit

/// Game Center integration: leaderboards (all-time and daily) and friends' scores.
/// The full plan, including App Store Connect setup, lives in docs/GAMECENTER.md.
///
/// Everything here is a no-op while `isEnabled` is false, so the app builds and runs without the
/// Game Center capability or leaderboards existing yet.
@MainActor
final class GameCenterService: NSObject, GKGameCenterControllerDelegate {
    static let shared = GameCenterService()

    /// Flip to true after: (1) adding the Game Center capability to the Hadron64 target,
    /// (2) creating the leaderboards in `Leaderboard` in App Store Connect.
    static let isEnabled = false

    private(set) var isAuthenticated = false

    // MARK: Authentication

    /// Install the authentication handler. Game Center calls it again whenever auth state changes,
    /// so this only needs to run once per launch.
    func authenticate() {
        guard Self.isEnabled else { return }
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            if let viewController {
                // Game Center wants to show its sign-in sheet.
                Self.topViewController()?.present(viewController, animated: true)
                return
            }
            self?.isAuthenticated = GKLocalPlayer.local.isAuthenticated && error == nil
            // The access point is Apple's floating badge that opens the Game Center dashboard
            // (leaderboards, friends, profile). Shown top-leading on the home screen only.
            GKAccessPoint.shared.location = .topLeading
            GKAccessPoint.shared.isActive = self?.isAuthenticated ?? false
        }
    }

    /// Hide the access point during play so it doesn't cover cards.
    func setAccessPointVisible(_ visible: Bool) {
        guard Self.isEnabled, isAuthenticated else { return }
        GKAccessPoint.shared.isActive = visible
    }

    // MARK: Scores

    /// Send a finished game to its leaderboards. Called from `StatsStore.log(_ game:)`.
    func submit(_ game: GameRecord) {
        guard Self.isEnabled, isAuthenticated, !game.usedHints, let ids = Leaderboard.ids(for: game.mode),
              let score = Leaderboard.score(for: game) else { return }
        Task {
            do {
                try await GKLeaderboard.submitScore(score, context: 0, player: GKLocalPlayer.local, leaderboardIDs: ids)
            } catch {
                // Game Center queues and retries submissions itself when offline; just log.
                print("Game Center submit failed: \(error)")
            }
        }
    }

    // MARK: Friends

    /// Ask permission to read the player's friends list (shows the NSGKFriendListUsageDescription prompt).
    func requestFriendsAccess() async -> Bool {
        guard Self.isEnabled, isAuthenticated else { return false }
        do {
            switch try await GKLocalPlayer.local.loadFriendsAuthorizationStatus() {
            case .authorized: return true
            case .notDetermined:
                _ = try await GKLocalPlayer.local.loadFriends()
                return try await GKLocalPlayer.local.loadFriendsAuthorizationStatus() == .authorized
            default: return false
            }
        } catch {
            return false
        }
    }

    /// Friends' entries (plus the local player's) on one leaderboard, for an in-app friends board.
    func friendEntries(mode: GameMode, daily: Bool) async -> [GKLeaderboard.Entry] {
        guard Self.isEnabled, isAuthenticated,
              let id = (daily ? Leaderboard.dailyID : Leaderboard.allTimeID)(mode) else { return [] }
        do {
            let boards = try await GKLeaderboard.loadLeaderboards(IDs: [id])
            guard let board = boards.first else { return [] }
            let (local, entries, _) = try await board.loadEntries(for: .friendsOnly, timeScope: .allTime, range: NSRange(location: 1, length: 50))
            return ([local].compactMap { $0 } + entries).uniqued()
        } catch {
            return []
        }
    }

    /// Adding friends happens in Game Center itself; this opens Apple's friend-request UI.
    func presentAddFriends() {
        guard Self.isEnabled, isAuthenticated, let top = Self.topViewController() else { return }
        try? GKLocalPlayer.local.presentFriendRequestCreator(from: top)
    }

    /// Apple's full leaderboard UI (global / friends, today / all time).
    func presentLeaderboard(for mode: GameMode) {
        guard Self.isEnabled, isAuthenticated, let id = Leaderboard.allTimeID(mode) else { return }
        let vc = GKGameCenterViewController(leaderboardID: id, playerScope: .friendsOnly, timeScope: .allTime)
        vc.gameCenterDelegate = self
        Self.topViewController()?.present(vc, animated: true)
    }

    nonisolated func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
        Task { @MainActor in gameCenterViewController.dismiss(animated: true) }
    }

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

/// Leaderboard identifiers. These must match App Store Connect exactly.
/// Each scored mode has a Classic (all-time) board and a Recurring board that resets daily.
enum Leaderboard {
    static func allTimeID(_ mode: GameMode) -> String? { slug(mode).map { "h64.\($0).alltime" } }
    static func dailyID(_ mode: GameMode) -> String? { slug(mode).map { "h64.\($0).daily" } }

    static func ids(for mode: GameMode) -> [String]? {
        guard let a = allTimeID(mode), let d = dailyID(mode) else { return nil }
        return [a, d]
    }

    /// Only the main modes get public boards; training is personal.
    private static func slug(_ mode: GameMode) -> String? {
        switch mode {
        case .freePlay: "freeplay"
        case .timeTrialEasy: "timetrial.easy"
        case .timeTrialMedium: "timetrial.medium"
        case .timeTrialHard: "timetrial.hard"
        default: nil
        }
    }

    /// Free Play: completion time in hundredths of a second (board format "Elapsed Time – hundredths",
    /// sorted low to high). Abandoned decks never reach here. Time Trial: cards collected (Integer, high to low).
    static func score(for game: GameRecord) -> Int? {
        if game.mode.isTimeTrial { return game.cardsCollected }
        return game.completed ? Int((game.duration * 100).rounded()) : nil
    }
}

private extension Array where Element == GKLeaderboard.Entry {
    func uniqued() -> [Element] {
        var seen = Set<String>()
        return filter { seen.insert($0.player.gamePlayerID).inserted }
    }
}
