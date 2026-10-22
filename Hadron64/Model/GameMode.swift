import Foundation

/// Every way of playing. Stats are recorded per mode; the raw values are persisted, so don't rename them.
enum GameMode: String, Codable, CaseIterable, Identifiable, Hashable {
    case freePlay
    case timeTrialEasy, timeTrialMedium, timeTrialHard
    case simple3, simple4, simple5
    case remainder
    case remainderMatch
    case setSize

    var id: String { rawValue }

    var title: String {
        switch self {
        case .freePlay: "Free Play"
        case .timeTrialEasy: "Time Trial · Easy"
        case .timeTrialMedium: "Time Trial · Medium"
        case .timeTrialHard: "Time Trial · Hard"
        case .simple3: "Simple Cards · 3"
        case .simple4: "Simple Cards · 4"
        case .simple5: "Simple Cards · 5"
        case .remainder: "Remainder"
        case .remainderMatch: "Remainder Matching"
        case .setSize: "Set Size"
        }
    }

    /// Which dots exist in this mode's deck.
    var dotMask: Int {
        switch self {
        case .simple3: Dot.redSolid.bit | Dot.yellowSolid.bit | Dot.blueSolid.bit              // solids only
        case .simple4: Dot.redSolid.bit | Dot.redStriped.bit | Dot.blueSolid.bit | Dot.blueStriped.bit  // no yellow
        case .simple5: CardMath.fullMask & ~Dot.yellowStriped.bit                                  // all but yellow striped
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

    /// Starting clock and per-set bonus, in seconds.
    var timeTrial: (start: TimeInterval, bonus: TimeInterval)? {
        switch self {
        case .timeTrialEasy: (60, 40)
        case .timeTrialMedium: (40, 20)
        case .timeTrialHard: (20, 10)
        default: nil
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
