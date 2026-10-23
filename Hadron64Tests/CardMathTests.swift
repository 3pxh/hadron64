import XCTest
@testable import Hadron64

final class CardMathTests: XCTestCase {
    func testFullDeckIs1Through63AndCancels() {
        let deck = CardMath.deck()
        XCTAssertEqual(deck, Array(1...63))
        XCTAssertEqual(CardMath.parity(deck), 0)
    }

    func testSimpleDecksOnlyUseTheirDotsAndCancel() {
        for mode in [GameMode.simple4, .simple5] {
            let deck = CardMath.deck(mask: mode.dotMask)
            XCTAssertEqual(deck.count, (1 << mode.dotCount) - 1, "\(mode)")
            XCTAssertTrue(deck.allSatisfy { $0 & ~mode.dotMask == 0 })
            XCTAssertEqual(CardMath.parity(deck), 0)
        }
        XCTAssertEqual(GameMode.simple4.dealSize, 5)
        XCTAssertEqual(GameMode.simple5.dealSize, 6)
    }

    func testExtraHardDeckAddsTheBackgroundAsASeventhProperty() {
        let deck = CardMath.deck(mask: GameMode.extraHard.dotMask)
        XCTAssertEqual(deck.count, 127)
        XCTAssertEqual(Set(deck), Set(1...127))
        XCTAssertEqual(CardMath.parity(deck), 0, "every property appears in exactly half the deck")
        XCTAssertEqual(GameMode.extraHard.dealSize, 8)
        XCTAssertEqual(TableLayout.rows(for: 8), [3, 2, 3])
        XCTAssertEqual(CardMath.deck().count, 63, "other decks don't gain shaded cards")
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

    func testRemainderDealIsNeverEmpty() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<200 {
            let cards = CardMath.remainderDeal(using: &rng)
            XCTAssertEqual(Set(cards).count, 7)
            XCTAssertNotEqual(CardMath.parity(cards), 0)
        }
    }

    @MainActor
    func testTutorialHandsHaveTheIntendedSets() {
        let sets = TutorialModel.fixedHands.map { CardMath.allSets(in: $0) }
        XCTAssertEqual(sets.count, 2)
        XCTAssertEqual(sets[0].map(Set.init), [[1, 3, 2]])
        XCTAssertEqual(sets[1].map(Set.init), [[32, 2, 34]], "10 is the decoy: its yellow can't cancel")
    }

    func testFoundSetCancelsPairByPair() {
        // {Y░ R●} {R● B░} {Y░ B░}: yellow, then red, then blue, in reading order.
        let pairs = CardMath.cancellingPairs([3, 6, 5])
        XCTAssertEqual(pairs.map { [$0.first, $0.second, $0.bit] }, [[3, 5, 1], [3, 6, 2], [6, 5, 4]])
        // Four cards sharing a dot cancel it in two pairs; the background (Extra Hard) comes last.
        let shaded = [1 | 64, 1 | 64 | 8, 1 | 2, 1 | 2 | 8]
        let bits = CardMath.cancellingPairs(shaded).map(\.bit)
        XCTAssertEqual(bits.filter { $0 == 1 }.count, 2)
        XCTAssertEqual(bits.last, 64)
    }

    func testDotsCancelInPairsInPickOrder() {
        // {Y░} {Y░ R●} {Y░ B░}: the first two yellows cancel, and the third stays on the latest card.
        XCTAssertEqual(CardMath.cancelled([1, 3, 5]), [1: 1, 3: 1, 5: 0])
        XCTAssertEqual(CardMath.cancelled([5, 3, 1]), [5: 5 & ~4, 3: 1, 1: 0])
        XCTAssertEqual(CardMath.cancelled([1, 3, 2]), [1: 1, 3: 3, 2: 2], "a set cancels completely")
    }

    @MainActor
    func testTutorialDotsCancelInPairs() {
        let model = TutorialModel()
        model.start()                                       // {Y░} {Y░ R●} {R●}
        model.toggle(1)
        XCTAssertEqual(model.cancelled[1], 0, "nothing to pair with yet")
        model.toggle(3)
        XCTAssertEqual(model.cancelled[1], 1, "the yellows cancel")
        XCTAssertEqual(model.cancelled[3], 1, "the red stays")
        model.toggle(1)
        XCTAssertEqual(model.cancelled[3], 0, "putting a card down brings its partner's dot back")
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
        store.log(FindEvent(mode: .remainder, duration: 2.5, cards: [1, 2, 3]))
        let reloaded = StatsStore(fileURL: url)
        XCTAssertEqual(reloaded.events.first?.cards, [1, 2, 3])
        XCTAssertEqual(reloaded.events.first?.mode, .remainder)
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
