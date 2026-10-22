import Foundation

/// Everything Hadron 64 registers with Game Center, in one place: leaderboards, achievements,
/// challenges and activities. Each entry mirrors one record in App Store Connect, and the IDs must
/// match it exactly. Names and descriptions here are what to type into App Store Connect (English);
/// players see App Store Connect's copy, not these strings, so they aren't localized in the app.
///
/// To add or change something: edit it here, update the setup sheet (linked in docs/GAMECENTER.md),
/// then make the same change in App Store Connect. Never reuse or rename a live ID; retire it and
/// make a new one instead.
enum GameCenterCatalog {

    // MARK: - Leaderboards

    /// Modes with public boards. Training stays personal.
    static let leaderboards: [Leaderboard] = [
        Leaderboard(id: "h64.freeplay.alltime", mode: .freePlay, daily: false, name: "Fastest Deck"),
        Leaderboard(id: "h64.freeplay.daily", mode: .freePlay, daily: true, name: "Fastest Deck Today"),
        Leaderboard(id: "h64.timetrial.easy.alltime", mode: .timeTrialEasy, daily: false, name: "Time Trial · Easy"),
        Leaderboard(id: "h64.timetrial.easy.daily", mode: .timeTrialEasy, daily: true, name: "Time Trial · Easy Today"),
        Leaderboard(id: "h64.timetrial.medium.alltime", mode: .timeTrialMedium, daily: false, name: "Time Trial · Medium"),
        Leaderboard(id: "h64.timetrial.medium.daily", mode: .timeTrialMedium, daily: true, name: "Time Trial · Medium Today"),
        Leaderboard(id: "h64.timetrial.hard.alltime", mode: .timeTrialHard, daily: false, name: "Time Trial · Hard"),
        Leaderboard(id: "h64.timetrial.hard.daily", mode: .timeTrialHard, daily: true, name: "Time Trial · Hard Today"),
    ]

    // MARK: - Achievements

    /// Game Center allows at most 1,000 points across all achievements and 100 per achievement.
    /// `progress` returns 0...1 from the player's whole local history, so players who played before
    /// Game Center was switched on get credit for it on their next launch.
    static let achievements: [Achievement] = [
        Achievement(id: "h64.ach.first_deck", points: 10,
                    title: "First Light",
                    unearned: "Clear a Free Play deck.",
                    earned: "You cleared your first deck.") { h in
            h.completedDecks.isEmpty ? 0 : 1
        },
        Achievement(id: "h64.ach.deck_10min", points: 20,
                    title: "Ten Minute Deck",
                    unearned: "Clear a Free Play deck in under 10 minutes without hints.",
                    earned: "You cleared a deck in under 10 minutes.") { h in
            h.bestCleanDeck.map { $0 < 10 * 60 ? 1 : 0 } ?? 0
        },
        Achievement(id: "h64.ach.deck_7min", points: 30,
                    title: "Seven Minute Deck",
                    unearned: "Clear a Free Play deck in under 7 minutes without hints.",
                    earned: "You cleared a deck in under 7 minutes.") { h in
            h.bestCleanDeck.map { $0 < 7 * 60 ? 1 : 0 } ?? 0
        },
        Achievement(id: "h64.ach.deck_5min", points: 50,
                    title: "Five Minute Deck",
                    unearned: "Clear a Free Play deck in under 5 minutes without hints.",
                    earned: "You cleared a deck in under 5 minutes.") { h in
            h.bestCleanDeck.map { $0 < 5 * 60 ? 1 : 0 } ?? 0
        },
        Achievement(id: "h64.ach.deck_3min", points: 100,
                    title: "Three Minute Deck",
                    unearned: "Clear a Free Play deck in under 3 minutes without hints.",
                    earned: "You cleared a deck in under 3 minutes.") { h in
            h.bestCleanDeck.map { $0 < 3 * 60 ? 1 : 0 } ?? 0
        },
        Achievement(id: "h64.ach.decks_10", points: 20,
                    title: "Regular",
                    unearned: "Clear 10 Free Play decks.",
                    earned: "You cleared 10 decks.") { h in
            Double(h.completedDecks.count) / 10
        },
        Achievement(id: "h64.ach.decks_100", points: 75,
                    title: "Centurion",
                    unearned: "Clear 100 Free Play decks.",
                    earned: "You cleared 100 decks.") { h in
            Double(h.completedDecks.count) / 100
        },
        Achievement(id: "h64.ach.sets_1000", points: 50,
                    title: "A Thousand Sets",
                    unearned: "Find 1,000 sets.",
                    earned: "You found 1,000 sets.") { h in
            Double(h.deckSets.count) / 1000
        },
        Achievement(id: "h64.ach.seven_set", points: 20, hidden: true,
                    title: "Full House",
                    unearned: "Find a set of seven cards.",
                    earned: "You found a set of seven cards.") { h in
            h.deckSets.contains { $0.size == 7 } ? 1 : 0
        },
        // Time trials deal from an endless deck, so these ask for a whole deck's worth of cards in one game.
        Achievement(id: "h64.ach.tt_easy_63", points: 30,
                    title: "Beat the Clock",
                    unearned: "Collect 63 cards in one Time Trial · Easy game.",
                    earned: "You collected 63 cards in Time Trial · Easy.") { h in
            Double(h.mostCards(in: .timeTrialEasy)) / 63
        },
        Achievement(id: "h64.ach.tt_medium_63", points: 50,
                    title: "Against the Clock",
                    unearned: "Collect 63 cards in one Time Trial · Medium game.",
                    earned: "You collected 63 cards in Time Trial · Medium.") { h in
            Double(h.mostCards(in: .timeTrialMedium)) / 63
        },
        Achievement(id: "h64.ach.tt_hard_63", points: 100,
                    title: "Faster Than Time",
                    unearned: "Collect 63 cards in one Time Trial · Hard game.",
                    earned: "You collected 63 cards in Time Trial · Hard.") { h in
            Double(h.mostCards(in: .timeTrialHard)) / 63
        },
        Achievement(id: "h64.ach.streak_7", points: 30,
                    title: "Seven Day Streak",
                    unearned: "Play on seven days in a row.",
                    earned: "You played seven days in a row.") { h in
            Double(h.longestDayStreak) / 7
        },
        Achievement(id: "h64.ach.training_all", points: 20,
                    title: "Well Rounded",
                    unearned: "Try every training mode.",
                    earned: "You tried every training mode.") { h in
            let training = GameMode.allCases.filter(\.isTraining)
            return Double(Set(h.events.map(\.mode)).intersection(training).count) / Double(training.count)
        },
    ]

    // MARK: - Challenges (iOS 26)

    /// Friends challenge each other on a leaderboard for a limited time, from the Games app or ours.
    /// Game Center scores challenges from leaderboard submissions, so they need no code beyond `submit`.
    /// Challenges build on the Classic (all-time) boards.
    static let challenges: [Challenge] = [
        Challenge(id: "h64.challenge.freeplay", leaderboardID: "h64.freeplay.alltime",
                  name: "Fastest Deck",
                  details: "Who can clear a whole deck fastest, without hints?"),
        Challenge(id: "h64.challenge.timetrial.easy", leaderboardID: "h64.timetrial.easy.alltime",
                  name: "Time Trial · Easy",
                  details: "Most cards collected before the clock runs out."),
        Challenge(id: "h64.challenge.timetrial.medium", leaderboardID: "h64.timetrial.medium.alltime",
                  name: "Time Trial · Medium",
                  details: "Most cards collected before the clock runs out."),
        Challenge(id: "h64.challenge.timetrial.hard", leaderboardID: "h64.timetrial.hard.alltime",
                  name: "Time Trial · Hard",
                  details: "Most cards collected before the clock runs out."),
    ]

    // MARK: - Activities (iOS 26)

    /// Deep links from the Games app and Game Center straight into a mode. App Store Connect stores
    /// `properties` with each activity; when a player taps it, Game Center hands them back to
    /// `GameCenterService`, which opens `mode`.
    static let activities: [Activity] = [
        Activity(id: "h64.activity.freeplay", mode: .freePlay,
                 name: "Free Play",
                 details: "Clear all 63 cards as fast as you can.",
                 achievementIDs: ["h64.ach.first_deck", "h64.ach.deck_10min", "h64.ach.deck_7min",
                                  "h64.ach.deck_5min", "h64.ach.deck_3min", "h64.ach.decks_10",
                                  "h64.ach.decks_100", "h64.ach.seven_set"]),
        Activity(id: "h64.activity.timetrial.easy", mode: .timeTrialEasy,
                 name: "Time Trial · Easy",
                 details: "Collect as many cards as you can. Every set adds 15 seconds.",
                 achievementIDs: ["h64.ach.tt_easy_63"]),
        Activity(id: "h64.activity.timetrial.medium", mode: .timeTrialMedium,
                 name: "Time Trial · Medium",
                 details: "Collect as many cards as you can. Every set adds 10 seconds.",
                 achievementIDs: ["h64.ach.tt_medium_63"]),
        Activity(id: "h64.activity.timetrial.hard", mode: .timeTrialHard,
                 name: "Time Trial · Hard",
                 details: "Collect as many cards as you can. Every set adds 5 seconds.",
                 achievementIDs: ["h64.ach.tt_hard_63"]),
    ]
}

// MARK: - Entry types

extension GameCenterCatalog {
    struct Leaderboard {
        let id: String
        let mode: GameMode
        /// Classic (all-time) when false; Recurring, resetting every 24 hours, when true.
        let daily: Bool
        let name: String

        /// Free Play: completion time in hundredths of a second ("Elapsed Time – hundredths", low to high).
        /// Time Trial: cards collected (Integer, high to low).
        func score(for game: GameRecord) -> Int? {
            guard game.mode == mode, !game.usedHints else { return nil }
            if mode.isTimeTrial { return game.cardsCollected }
            return game.completed ? Int((game.duration * 100).rounded()) : nil
        }
    }

    struct Achievement {
        let id: String
        let points: Int
        var hidden = false
        let title: String
        /// App Store Connect's "Pre-earned description".
        let unearned: String
        /// App Store Connect's "Post-earned description".
        let earned: String
        let progress: (History) -> Double
    }

    struct Challenge {
        let id: String
        let leaderboardID: String
        let name: String
        let details: String
    }

    struct Activity {
        let id: String
        let mode: GameMode
        let name: String
        let details: String
        let achievementIDs: [String]

        /// Enter these in App Store Connect as the activity's properties.
        var properties: [String: String] { [Self.modeKey: mode.rawValue] }
        static let modeKey = "mode"

        /// The mode's own leaderboards.
        var leaderboardIDs: [String] { GameCenterCatalog.leaderboards(for: mode).map(\.id) }
    }

    /// What achievement rules look at: the player's whole local history.
    struct History {
        let games: [GameRecord]
        let events: [FindEvent]

        var completedDecks: [GameRecord] { games.filter { $0.mode == .freePlay && $0.completed } }
        var bestCleanDeck: TimeInterval? { completedDecks.filter { !$0.usedHints }.map(\.duration).min() }
        /// Sets found in any deck mode (drills like Remainder don't find sets).
        var deckSets: [FindEvent] { events.filter(\.mode.isDeckMode) }

        func mostCards(in mode: GameMode) -> Int { games.filter { $0.mode == mode }.map(\.cardsCollected).max() ?? 0 }

        var longestDayStreak: Int {
            let calendar = Calendar.current
            let days = Set((games.map(\.date) + events.map(\.date)).map { calendar.startOfDay(for: $0) }).sorted()
            var longest = 0, run = 0
            var previous: Date?
            for day in days {
                let consecutive = previous.flatMap { calendar.date(byAdding: .day, value: 1, to: $0) } == day
                run = consecutive ? run + 1 : 1
                longest = max(longest, run)
                previous = day
            }
            return longest
        }
    }
}

// MARK: - Lookups

extension GameCenterCatalog {
    static func leaderboards(for mode: GameMode) -> [Leaderboard] { leaderboards.filter { $0.mode == mode } }

    static func leaderboard(for mode: GameMode, daily: Bool) -> Leaderboard? {
        leaderboards.first { $0.mode == mode && $0.daily == daily }
    }

    static func activity(id: String) -> Activity? { activities.first { $0.id == id } }
    static func activity(for mode: GameMode) -> Activity? { activities.first { $0.mode == mode } }
}
