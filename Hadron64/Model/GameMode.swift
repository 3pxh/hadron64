import Foundation

/// Every way of playing. Stats are recorded per mode; the raw values are persisted, so don't rename them.
enum GameMode: String, Codable, CaseIterable, Identifiable, Hashable {
    case freePlay
    case timeTrialEasy, timeTrialMedium, timeTrialHard
    case simple4, simple5
    case simple4TrialEasy, simple4TrialHard
    case simple5TrialEasy, simple5TrialHard
    case remainder
    /// Retired modes. Kept so saved stats that mention them still decode; never offered or listed.
    case remainderMatch, setSize
    case simple3, simple3TrialEasy, simple3TrialHard
    case extraHard
    case extraHardTrialEasy, extraHardTrialHard

    var id: String { rawValue }

    /// Modes that are still played (and shown in Statistics).
    static var playable: [GameMode] { allCases.filter { !retired.contains($0) } }
    private static let retired: Set<GameMode> = [.remainderMatch, .setSize, .simple3, .simple3TrialEasy, .simple3TrialHard]

    var title: String {
        switch self {
        case .freePlay: String(localized: "Free Play")
        case .timeTrialEasy: String(localized: "Time Trial · Easy")
        case .timeTrialMedium: String(localized: "Time Trial · Medium")
        case .timeTrialHard: String(localized: "Time Trial · Hard")
        case .simple4: String(localized: "Simple Cards · 4")
        case .simple5: String(localized: "Simple Cards · 5")
        case .simple4TrialEasy: String(localized: "Simple Cards · 4 · Easy Trial")
        case .simple4TrialHard: String(localized: "Simple Cards · 4 · Hard Trial")
        case .simple5TrialEasy: String(localized: "Simple Cards · 5 · Easy Trial")
        case .simple5TrialHard: String(localized: "Simple Cards · 5 · Hard Trial")
        case .remainder: String(localized: "Remainder")
        case .remainderMatch: String(localized: "Remainder Matching")
        case .setSize: String(localized: "Set Size")
        case .simple3, .simple3TrialEasy, .simple3TrialHard: String(localized: "Simple Cards")
        case .extraHard: String(localized: "Extra Hard")
        case .extraHardTrialEasy: String(localized: "Extra Hard · Easy Trial")
        case .extraHardTrialHard: String(localized: "Extra Hard · Hard Trial")
        }
    }

    /// Which dots exist in this mode's deck. Extra Hard also includes the background bit, which counts as a seventh dot.
    var dotMask: Int {
        switch self {
        case _ where base != self: base.dotMask                                                  // trials use their base mode's cards
        case .simple4: Dot.redSolid.bit | Dot.redStriped.bit | Dot.blueSolid.bit | Dot.blueStriped.bit  // no yellow
        case .simple5: CardMath.fullMask & ~Dot.yellowStriped.bit                                  // all but yellow striped
        case .extraHard: CardMath.fullMask | CardMath.backgroundBit                                // 127 cards, deal 8
        default: CardMath.fullMask
        }
    }

    var dotCount: Int { dotMask.nonzeroBitCount }

    /// N dots need N+1 cards on the table to guarantee a set exists (N+1 vectors in an N-dimensional space are dependent).
    var dealSize: Int { dotCount + 1 }

    /// Modes that are played by burning through a deck.
    var isDeckMode: Bool {
        switch self {
        case .remainder, .remainderMatch, .setSize: false
        default: true
        }
    }

    var isTimeTrial: Bool { timeTrial != nil }

    /// Time trials never run out of cards: when the deck is used up a fresh one is shuffled in,
    /// so the board always has its full deal and the game ends only when the clock does.
    var hasEndlessDeck: Bool { isTimeTrial }

    /// Training modes are limited per day without the supporter unlock (see `Supporter`).
    var isTraining: Bool {
        switch self {
        case .freePlay, .timeTrialEasy, .timeTrialMedium, .timeTrialHard: false
        default: true
        }
    }

    /// Starting clock and per-set bonus, in seconds.
    var timeTrial: (start: TimeInterval, bonus: TimeInterval)? {
        switch self {
        case .timeTrialEasy: (60, 15)
        case .timeTrialMedium: (40, 10)
        case .timeTrialHard: (20, 5)
        case .simple4TrialEasy, .simple5TrialEasy: (20, 10)
        case .simple4TrialHard, .simple5TrialHard: (10, 5)
        case .extraHardTrialEasy: (60, 30)
        case .extraHardTrialHard: (30, 15)
        default: nil
        }
    }

    /// The time trials played with this mode's cards, easy then hard (Simple Cards and Extra Hard).
    var trials: (easy: GameMode, hard: GameMode)? {
        switch self {
        case .simple4: (.simple4TrialEasy, .simple4TrialHard)
        case .simple5: (.simple5TrialEasy, .simple5TrialHard)
        case .extraHard: (.extraHardTrialEasy, .extraHardTrialHard)
        default: nil
        }
    }

    /// The training mode whose cards a trial uses; itself for everything else.
    var base: GameMode {
        switch self {
        case .simple4TrialEasy, .simple4TrialHard: .simple4
        case .simple5TrialEasy, .simple5TrialHard: .simple5
        case .extraHardTrialEasy, .extraHardTrialHard: .extraHard
        default: self
        }
    }

    /// Set sizes that can occur in this mode (cards are distinct and non-empty, so never fewer than 3).
    var possibleSetSizes: ClosedRange<Int> {
        switch self {
        case .remainder: 7...7
        default: 3...min(7, dealSize)
        }
    }
}
