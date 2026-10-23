import SwiftUI

/// A card is just a number 1...63. Each of its six bits says whether one dot is present.
/// Bit index = column * 3 + row, matching the original print layout, so card 63 shows every dot.
///
///      col 0            col 1
///   row 0  bit 0 yellow striped   bit 3 yellow solid
///   row 1  bit 1 red solid        bit 4 red striped
///   row 2  bit 2 blue striped     bit 5 blue solid
///
/// A set of cards is valid when every dot appears an even number of times — i.e. the XOR of
/// the card numbers is zero. This turns the whole game into linear algebra over GF(2)^6.
///
/// Extra Hard adds a seventh property, bit 6: a shaded background, which must also come in pairs. Its cards are 1...127.
enum Dot: Int, CaseIterable, Identifiable {
    case yellowStriped = 0, redSolid, blueStriped, yellowSolid, redStriped, blueSolid

    var id: Int { rawValue }
    var bit: Int { 1 << rawValue }
    var column: Int { rawValue / 3 }
    var row: Int { rawValue % 3 }
    /// Dots alternate solid/striped in a checkerboard.
    var isSolid: Bool { (row + column) % 2 == 1 }
    var color: Color { Palette.rows[row] }

    /// What VoiceOver calls the dot when it's a button (Remainder drill).
    var accessibilityName: String {
        switch self {
        case .yellowStriped: String(localized: "Striped yellow")
        case .yellowSolid: String(localized: "Solid yellow")
        case .redSolid: String(localized: "Solid red")
        case .redStriped: String(localized: "Striped red")
        case .blueStriped: String(localized: "Striped blue")
        case .blueSolid: String(localized: "Solid blue")
        }
    }

    /// The order dots are read off a card (row by row, left to right). Used by the remainder line.
    static let readingOrder: [Dot] = [.yellowStriped, .yellowSolid, .redSolid, .redStriped, .blueStriped, .blueSolid]
}

/// Card dimensions, in the print reference's 300ppi pixel units (2.5" x 3.5" plus 1/16" bleed).
/// Everything on screen is scaled from these so the proportions match the printed deck.
enum CardGeometry {
    static let bleed: CGFloat = 19
    static let width: CGFloat = 750 + 2 * bleed
    static let height: CGFloat = 1050 + 2 * bleed
    static let dotRadius: CGFloat = 81
    static let margin: CGFloat = 135
    static let spacerV: CGFloat = (height - (dotRadius * 6 + margin * 2)) / 2
    static let spacerH: CGFloat = width - (dotRadius * 4 + margin * 2)
    static let strokeWidth: CGFloat = 16
    /// Equal-width vertical bands across the inside of the outline, alternating white and color
    /// with white at both edges (so an odd count: 4 white, 3 colored).
    static let stripeBands = 7

    static var aspect: CGFloat { width / height }

    static func center(of dot: Dot) -> CGPoint {
        CGPoint(x: margin + CGFloat(dot.column) * (dotRadius * 2 + spacerH) + dotRadius,
                y: margin + CGFloat(dot.row) * (dotRadius * 2 + spacerV) + dotRadius)
    }
}

enum CardMath {
    static let fullMask = 0b111111
    /// The shaded background (Extra Hard only).
    static let backgroundBit = 1 << 6

    static func parity<S: Sequence>(_ cards: S) -> Int where S.Element == Int {
        cards.reduce(0, ^)
    }

    /// Every non-empty card using only the properties in `mask`. For the full mask that's 1...63; with the
    /// background bit too, 1...127.
    /// Each dot appears in exactly half of these cards, so the whole deck always XORs to zero —
    /// which means whatever is left on the board at the end is always a valid set.
    static func deck(mask: Int = fullMask) -> [Int] {
        (1...(fullMask | backgroundBit)).filter { $0 & ~mask == 0 }
    }

    /// The dots that have cancelled on each picked card. Each kind of dot cancels in pairs in the order the cards were
    /// picked, so an odd one out stays on the latest card that has it.
    static func cancelled(_ picks: [Int]) -> [Int: Int] {
        var result: [Int: Int] = [:]
        var left = parity(picks)
        for card in picks.reversed() {
            result[card] = card & ~left
            left &= ~card
        }
        return result
    }

    /// How a set's dots cancel, one pair at a time: property by property in reading order (the shaded background
    /// last), each pairing up the cards that have it in the order given.
    static func cancellingPairs(_ set: [Int]) -> [(first: Int, second: Int, bit: Int)] {
        let bits = Dot.readingOrder.map(\.bit) + [backgroundBit]
        return bits.flatMap { bit in
            let having = set.filter { $0 & bit != 0 }
            return stride(from: 0, to: having.count - 1, by: 2).map { (having[$0], having[$0 + 1], bit) }
        }
    }

    /// All non-empty subsets of `cards` whose dots cancel.
    static func allSets(in cards: [Int]) -> [[Int]] {
        guard !cards.isEmpty, cards.count < 16 else { return [] }
        var result: [[Int]] = []
        for subset in 1..<(1 << cards.count) {
            var x = 0
            for i in cards.indices where subset & (1 << i) != 0 { x ^= cards[i] }
            if x == 0 {
                result.append(cards.indices.filter { subset & (1 << $0) != 0 }.map { cards[$0] })
            }
        }
        return result
    }

    /// The valid set closest to the player's current selection (smallest symmetric difference,
    /// then smallest size). Used for tutorial hints.
    static func nearestSet(in cards: [Int], to selection: Set<Int>) -> [Int]? {
        allSets(in: cards).min { a, b in
            let da = Set(a).symmetricDifference(selection).count
            let db = Set(b).symmetricDifference(selection).count
            return da != db ? da < db : a.count < b.count
        }
    }

    /// Seven distinct cards whose remainder isn't empty (so the remainder drill always has an answer to enter).
    static func remainderDeal<R: RandomNumberGenerator>(using rng: inout R) -> [Int] {
        while true {
            let cards = Array(deck().shuffled(using: &rng).prefix(7))
            if parity(cards) != 0 { return cards }
        }
    }
}
