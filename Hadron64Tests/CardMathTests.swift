import XCTest
@testable import Hadron64

final class CardMathTests: XCTestCase {
    func testFullDeckIs1Through63AndCancels() {
        let deck = CardMath.deck()
        XCTAssertEqual(deck, Array(1...63))
        XCTAssertEqual(CardMath.parity(deck), 0)
    }

    func testSimpleDecksOnlyUseTheirDotsAndCancel() {
        for mode in [GameMode.simple3, .simple4, .simple5] {
            let deck = CardMath.deck(mask: mode.dotMask)
            XCTAssertEqual(deck.count, (1 << mode.dotCount) - 1, "\(mode)")
            XCTAssertTrue(deck.allSatisfy { $0 & ~mode.dotMask == 0 })
            XCTAssertEqual(CardMath.parity(deck), 0)
        }
        XCTAssertEqual(GameMode.simple3.dealSize, 4)
        XCTAssertEqual(GameMode.simple5.dealSize, 6)
    }

    func testDotLayoutMatchesPrintReference() {
        // Bit = column * 3 + row; solid when (row + column) is odd.
        XCTAssertFalse(Dot.yellowStriped.isSolid)
        XCTAssertTrue(Dot.redSolid.isSolid)
        XCTAssertTrue(Dot.yellowSolid.isSolid)
        XCTAssertEqual(Dot.yellowSolid.column, 1)
        XCTAssertEqual(Dot.blueSolid.row, 2)
    }

    func testAnySevenCardsContainASet() {
        for _ in 0..<500 {
            let hand = Array(CardMath.deck().shuffled().prefix(7))
            XCTAssertFalse(CardMath.allSets(in: hand).isEmpty)
        }
    }

    func testUniqueSetDealHasExactlyOneSetOfRequestedSize() {
        var rng = SystemRandomNumberGenerator()
        for size in 3...7 {
            for _ in 0..<100 {
                let deal = CardMath.uniqueSetDeal(size: size, using: &rng)
                XCTAssertEqual(Set(deal.cards).count, 7)
                XCTAssertFalse(deal.cards.contains(0))
                let sets = CardMath.allSets(in: deal.cards)
                XCTAssertEqual(sets.count, 1)
                XCTAssertEqual(Set(sets[0]), Set(deal.set))
                XCTAssertEqual(deal.set.count, size)
            }
        }
    }

    func testRemainderDealIsNeverEmpty() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            let cards = CardMath.remainderDeal(using: &rng)
            XCTAssertEqual(Set(cards).count, 7)
            XCTAssertNotEqual(CardMath.parity(cards), 0)
        }
    }

    func testTutorialHandsHaveTheIntendedSets() {
        let sets = TutorialModel.scripted.map { CardMath.allSets(in: $0) }
        XCTAssertEqual(sets[0].map(Set.init), [[3, 6, 5]])
        XCTAssertEqual(sets[1].map(Set.init), [[9, 18, 27]])
        XCTAssertEqual(sets[2].map(Set.init), [[11, 22, 44, 49]])
    }

    func testHistogramPutsOutliersInLastBin() {
        let bins = Histogram.bins((1...99).map(Double.init) + [500])
        XCTAssertEqual(bins.map(\.count).reduce(0, +), 100)
        XCTAssertLessThan(bins.last!.upper, 500)
        XCTAssertEqual(bins.first?.lower, 0)
    }
}

@MainActor
final class StatsStoreTests: XCTestCase {
    func testRecordsAndAverages() {
        let store = StatsStore(fileURL: nil)
        let first = store.log(GameRecord(mode: .freePlay, duration: 300, completed: true, cardsCollected: 63, setsFound: 12))
        XCTAssertTrue(first.isNewRecord)
        let slower = store.log(GameRecord(mode: .freePlay, duration: 400, completed: true, cardsCollected: 63, setsFound: 12))
        XCTAssertFalse(slower.isNewRecord)
        XCTAssertEqual(slower.best, 300)
        XCTAssertEqual(slower.average, 350)

        store.log(GameRecord(mode: .timeTrialHard, duration: 50, completed: false, cardsCollected: 10, setsFound: 2))
        let better = store.log(GameRecord(mode: .timeTrialHard, duration: 80, completed: false, cardsCollected: 20, setsFound: 4))
        XCTAssertTrue(better.isNewRecord)
        XCTAssertEqual(better.best, 20)
    }

    func testPersistsToDisk() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = StatsStore(fileURL: url)
        store.log(FindEvent(mode: .setSize, duration: 2.5, cards: [1, 2, 3]))
        let reloaded = StatsStore(fileURL: url)
        XCTAssertEqual(reloaded.events.first?.cards, [1, 2, 3])
        XCTAssertEqual(reloaded.events.first?.mode, .setSize)
    }
}

final class RemainderMatchTests: XCTestCase {
    func testYellowOnlyRemainders() {
        XCTAssertTrue(CardMath.isYellowOnlyRemainder(Dot.yellowStriped.bit))
        XCTAssertTrue(CardMath.isYellowOnlyRemainder(CardMath.yellowMask))
        XCTAssertFalse(CardMath.isYellowOnlyRemainder(0))
        XCTAssertFalse(CardMath.isYellowOnlyRemainder(Dot.yellowSolid.bit | Dot.redSolid.bit))
    }

    /// Brute-force check that `hasYellowMatch` agrees with the literal rule: two different groups
    /// with the same yellow-only remainder.
    func testHasYellowMatchAgreesWithBruteForce() {
        for _ in 0..<300 {
            let hand = Array(CardMath.deck().shuffled().prefix(7))
            var byRemainder: [Int: Int] = [:]
            for subset in 1..<(1 << 7) {
                let p = hand.indices.filter { subset & (1 << $0) != 0 }.reduce(0) { $0 ^ hand[$1] }
                if CardMath.isYellowOnlyRemainder(p) { byRemainder[p, default: 0] += 1 }
            }
            XCTAssertEqual(CardMath.hasYellowMatch(hand), byRemainder.values.contains { $0 >= 2 })
        }
    }
}

@MainActor
final class HintTests: XCTestCase {
    func testHintRevealsSizeThenACard() {
        let game = DeckGame(mode: .freePlay)
        game.start()
        let board = game.table.boardCards
        game.hint()
        XCTAssertEqual(game.hintLevel, 1)
        let smallest = CardMath.allSets(in: board).map(\.count).min()
        XCTAssertEqual(game.hintSet.count, smallest)
        game.hint()
        XCTAssertEqual(game.hintLevel, 2)
        switch game.hintSet.count {
        case 3, 4: XCTAssertTrue(game.hintIncluded.isSubset(of: Set(game.hintSet)))
        case 5, 6: XCTAssertTrue(game.hintExcluded.isDisjoint(with: Set(game.hintSet)))
        default: XCTAssertEqual(game.hintIncluded, Set(board))
        }
        game.hint()
        XCTAssertEqual(game.hintsUsed, 2)
    }

    func testHintsOnlyInFreePlay() {
        let game = DeckGame(mode: .timeTrialEasy)
        game.start()
        game.hint()
        XCTAssertEqual(game.hintLevel, 0)
    }
}
