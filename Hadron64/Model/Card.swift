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
enum Dot: Int, CaseIterable, Identifiable {
    case yellowStriped = 0, redSolid, blueStriped, yellowSolid, redStriped, blueSolid

    var id: Int { rawValue }
    var bit: Int { 1 << rawValue }
    var column: Int { rawValue / 3 }
    var row: Int { rawValue % 3 }
    /// Dots alternate solid/striped in a checkerboard.
    var isSolid: Bool { (row + column) % 2 == 1 }
    var color: Color { Palette.rows[row] }

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
    static let strokeWidth: CGFloat = 12
    static let stripeWidth: CGFloat = 14
    static let stripeSpacing: CGFloat = 25
    /// Offset of the first stripe from the dot's left edge, chosen so stripes sit symmetrically.
    static let stripeInset: CGFloat = 6

    static var aspect: CGFloat { width / height }

    static func center(of dot: Dot) -> CGPoint {
        CGPoint(x: margin + CGFloat(dot.column) * (dotRadius * 2 + spacerH) + dotRadius,
                y: margin + CGFloat(dot.row) * (dotRadius * 2 + spacerV) + dotRadius)
    }
}

enum CardMath {
    static let fullMask = 0b111111

    static func parity<S: Sequence>(_ cards: S) -> Int where S.Element == Int {
        cards.reduce(0, ^)
    }

    /// Every non-empty card using only the dots in `mask`. For the full mask that's 1...63.
    /// Each dot appears in exactly half of these cards, so the whole deck always XORs to zero —
    /// which means whatever is left on the board at the end is always a valid set.
    static func deck(mask: Int = fullMask) -> [Int] {
        (1...fullMask).filter { $0 & ~mask == 0 }
    }

    static let yellowMask = Dot.yellowStriped.bit | Dot.yellowSolid.bit

    /// A Remainder Matching group: some dots left over, and only yellow ones.
    static func isYellowOnlyRemainder(_ parity: Int) -> Bool {
        parity != 0 && parity & ~yellowMask == 0
    }

    /// Every remainder some subset of `cards` can produce (the GF(2) span).
    static func reachableRemainders(_ cards: [Int]) -> Set<Int> {
        cards.reduce(into: Set([0])) { span, card in span.formUnion(span.map { $0 ^ card }) }
    }

    /// Remainder Matching needs two different groups with the same yellow-only remainder r.
    /// If the cards contain a set S and some group G has remainder r, then G and G △ S both work;
    /// so it's enough that a set exists and some yellow-only r is reachable.
    static func hasYellowMatch(_ cards: [Int]) -> Bool {
        let reachable = reachableRemainders(cards)
        return reachable.count < 1 << cards.count   // some dependency, i.e. a set exists
            && reachable.contains(where: isYellowOnlyRemainder)
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

    /// Seven cards containing exactly one valid set, of the given size (3...7).
    ///
    /// Pick a random basis b1...b6 of GF(2)^6 and add c = b1 ^ ... ^ b(size-1). Seven vectors of rank six
    /// have a one-dimensional space of dependencies, so {b1, ..., b(size-1), c} is the only set.
    static func uniqueSetDeal<R: RandomNumberGenerator>(size: Int, using rng: inout R) -> (cards: [Int], set: [Int]) {
        precondition((3...7).contains(size))
        var basis: [Int] = []
        var span: Set<Int> = [0]
        while basis.count < 6 {
            let v = Int.random(in: 1...fullMask, using: &rng)
            guard !span.contains(v) else { continue }
            basis.append(v)
            span = span.union(span.map { $0 ^ v })
        }
        let members = Array(basis.prefix(size - 1))
        let closing = parity(members)
        return ((basis + [closing]).shuffled(using: &rng), members + [closing])
    }
}
