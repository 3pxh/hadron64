import GameKit
import Observation
import UIKit

/// Game Center integration: leaderboards, achievements, challenges, activities and friends' scores.
/// What exists (IDs, names, rules) lives in `GameCenterCatalog`; this class only talks to GameKit.
/// The plan and App Store Connect setup live in docs/GAMECENTER.md.
///
/// Everything here is a no-op while `isEnabled` is false, so the app builds and runs without the
/// Game Center capability or App Store Connect records existing yet.
@Observable @MainActor
final class GameCenterService: NSObject, GKGameCenterControllerDelegate, GKLocalPlayerListener {
    static let shared = GameCenterService()

    /// Flip to true after: (1) adding the Game Center capability to the Hadron64 target,
    /// (2) creating everything in `GameCenterCatalog` in App Store Connect.
    static let isEnabled = false

    private(set) var isAuthenticated = false
    /// Set when a Game Center activity asks to open a mode; `HomeView` starts it and clears this.
    var requestedMode: GameMode?

    @ObservationIgnored private weak var stats: StatsStore?
    /// Whole-percent progress Game Center already has per achievement; nil until loaded after sign-in.
    @ObservationIgnored private var reportedPercent: [String: Double]?
    /// The latest score submission, so the results screen can read ranks after it lands.
    @ObservationIgnored private var pendingSubmit: Task<Void, Never>?

    // MARK: Authentication

    /// Install the authentication handler. Game Center calls it again whenever auth state changes,
    /// so this only needs to run once per launch.
    func authenticate(stats: StatsStore) {
        guard Self.isEnabled else { return }
        self.stats = stats
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            guard let self else { return }
            if let viewController {
                // Game Center wants to show its sign-in sheet.
                Self.topViewController()?.present(viewController, animated: true)
                return
            }
            let wasAuthenticated = isAuthenticated
            isAuthenticated = GKLocalPlayer.local.isAuthenticated && error == nil
            // The access point is Apple's floating badge that opens the Game Center dashboard
            // (leaderboards, friends, profile). Shown top-leading on the home screen only.
            GKAccessPoint.shared.location = .topLeading
            GKAccessPoint.shared.isActive = isAuthenticated
            if isAuthenticated && !wasAuthenticated {
                // Activities arrive through the listener.
                GKLocalPlayer.local.register(self)
                loadAchievementProgress()
            }
        }
    }

    /// Hide the access point during play so it doesn't cover cards.
    func setAccessPointVisible(_ visible: Bool) {
        guard Self.isEnabled, isAuthenticated else { return }
        GKAccessPoint.shared.isActive = visible
    }

    // MARK: Scores

    /// Send a finished game to its leaderboards and update achievements. Called from `StatsStore.log(_ game:)`.
    func submit(_ game: GameRecord) {
        guard Self.isEnabled, isAuthenticated else { return }
        syncAchievements()
        let boards = GameCenterCatalog.leaderboards(for: game.mode)
        guard let score = boards.first?.score(for: game) else { return }
        // Every game is submitted: Game Center keeps each player's best per board.
        pendingSubmit = Task {
            do {
                try await GKLeaderboard.submitScore(score, context: 0, player: GKLocalPlayer.local,
                                                    leaderboardIDs: boards.map(\.id))
            } catch {
                // Game Center queues and retries submissions itself when offline; just log.
                print("Game Center submit failed: \(error)")
            }
        }
    }

    // MARK: Achievements

    private func loadAchievementProgress() {
        Task {
            let achievements = (try? await GKAchievement.loadAchievements()) ?? []
            reportedPercent = Dictionary(achievements.map { ($0.identifier, $0.percentComplete) }) { max($0, $1) }
            // Backfill from history: credit for games played before Game Center was on, or on another device.
            syncAchievements()
        }
    }

    /// Re-evaluate every achievement in `GameCenterCatalog` against local history and report whatever
    /// moved forward. Progress is reported in whole percents, so this is cheap to call after every find.
    func syncAchievements() {
        guard Self.isEnabled, isAuthenticated, var reported = reportedPercent, let stats else { return }
        let history = stats.gameCenterHistory
        let updates = GameCenterCatalog.achievements.compactMap { achievement -> GKAchievement? in
            let percent = (min(max(achievement.progress(history), 0), 1) * 100).rounded(.down)
            guard percent > reported[achievement.id, default: 0] else { return nil }
            reported[achievement.id] = percent
            let gk = GKAchievement(identifier: achievement.id)
            gk.percentComplete = percent
            gk.showsCompletionBanner = true
            return gk
        }
        reportedPercent = reported
        guard !updates.isEmpty else { return }
        Task {
            do {
                try await GKAchievement.report(updates)
            } catch {
                print("Game Center achievement report failed: \(error)")
            }
        }
    }

    // MARK: Friends

    /// Whether the player has let us read their friends list. With `prompt`, asks first if they haven't
    /// decided (shows the NSGKFriendListUsageDescription alert).
    func friendsAccess(prompt: Bool) async -> Bool {
        guard Self.isEnabled, isAuthenticated else { return false }
        do {
            switch try await GKLocalPlayer.local.loadFriendsAuthorizationStatus() {
            case .authorized: return true
            case .notDetermined where prompt:
                _ = try await GKLocalPlayer.local.loadFriends()
                return try await GKLocalPlayer.local.loadFriendsAuthorizationStatus() == .authorized
            default: return false
            }
        } catch {
            return false
        }
    }

    /// Friends' entries plus the local player's on one of a mode's boards, best first.
    func friendEntries(mode: GameMode, daily: Bool) async -> [GKLeaderboard.Entry] {
        guard Self.isEnabled, isAuthenticated,
              let id = GameCenterCatalog.leaderboard(for: mode, daily: daily)?.id else { return [] }
        do {
            guard let board = try await GKLeaderboard.loadLeaderboards(IDs: [id]).first else { return [] }
            // A Recurring board ignores the time scope and returns its current day.
            let (local, entries, _) = try await board.loadEntries(for: .friendsOnly, timeScope: .allTime,
                                                                  range: NSRange(location: 1, length: 50))
            var seen = Set<String>()
            return ([local].compactMap { $0 } + entries)
                .filter { seen.insert($0.player.gamePlayerID).inserted }
                .sorted { $0.rank < $1.rank }
        } catch {
            return []
        }
    }

    /// Where this game left the player on today's board among friends, once its submission lands.
    /// nil when signed out, friends access isn't granted, or no friend has played today.
    func dailyFriendsRank(after game: GameRecord) async -> (rank: Int, of: Int)? {
        guard Self.isEnabled, isAuthenticated, GameCenterCatalog.leaderboard(for: game.mode, daily: true) != nil,
              await friendsAccess(prompt: false) else { return nil }
        await pendingSubmit?.value
        let entries = await friendEntries(mode: game.mode, daily: true)
        guard entries.count > 1,
              let me = entries.first(where: { $0.player.gamePlayerID == GKLocalPlayer.local.gamePlayerID })
        else { return nil }
        return (me.rank, entries.count)
    }

    /// Adding friends happens in Game Center itself; this opens Apple's friend-request UI.
    func presentAddFriends() {
        guard Self.isEnabled, isAuthenticated, let top = Self.topViewController() else { return }
        try? GKLocalPlayer.local.presentFriendRequestCreator(from: top)
    }

    /// Apple's full leaderboard UI for one of a mode's boards.
    func presentLeaderboard(for mode: GameMode, daily: Bool, scope: GKLeaderboard.PlayerScope = .global) {
        guard Self.isEnabled, isAuthenticated,
              let id = GameCenterCatalog.leaderboard(for: mode, daily: daily)?.id else { return }
        let vc = GKGameCenterViewController(leaderboardID: id, playerScope: scope, timeScope: .allTime)
        vc.gameCenterDelegate = self
        Self.topViewController()?.present(vc, animated: true)
    }

    nonisolated func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
        Task { @MainActor in gameCenterViewController.dismiss(animated: true) }
    }

    // MARK: Challenges (iOS 26)

    var supportsChallenges: Bool {
        if #available(iOS 26.0, *) { Self.isEnabled && isAuthenticated } else { false }
    }

    /// Game Center's sheet for challenging friends on one of this mode's challenges.
    func presentChallenge(for mode: GameMode) {
        guard supportsChallenges else { return }
        let id = GameCenterCatalog.challenges.first { challenge in
            GameCenterCatalog.leaderboards(for: mode).contains { $0.id == challenge.leaderboardID }
        }?.id
        if #available(iOS 26.0, *) {
            if let id {
                GKAccessPoint.shared.trigger(challengeDefinitionID: id) {}
            } else {
                GKAccessPoint.shared.triggerForChallenges {}
            }
        }
    }

    // MARK: Activities (iOS 26)

    /// A player tapped one of our activities in the Games app or Game Center: open its mode.
    @available(iOS 26.0, *)
    nonisolated func player(_ player: GKPlayer, wantsToPlay activity: GKGameActivity,
                            completionHandler: @escaping (Bool) -> Void) {
        let id = activity.activityDefinition.identifier
        let raw = activity.properties[GameCenterCatalog.Activity.modeKey]
        Task { @MainActor in
            let mode = GameCenterCatalog.activity(id: id)?.mode ?? raw.flatMap(GameMode.init(rawValue:))
            requestedMode = mode
            completionHandler(mode != nil)
        }
    }

    // MARK: Helpers

    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

extension StatsStore {
    var gameCenterHistory: GameCenterCatalog.History { .init(games: games, events: events) }
}
