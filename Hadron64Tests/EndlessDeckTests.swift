import XCTest
@testable import Hadron64

@MainActor
final class EndlessDeckTests: XCTestCase {
    func testEndlessTableKeepsAFullDistinctBoardWithASetPastSeveralDecks() {
        let cards = CardMath.deck()
        let table = Table(slotCount: 7, deck: cards.shuffled(), endlessDeck: cards)
        table.deal()
        // ~6 decks' worth of finds.
        for _ in 0..<120 {
            let board = table.boardCards
            XCTAssertEqual(board.count, 7)
            XCTAssertEqual(Set(board).count, 7, "no duplicate cards on the board")
            guard let set = CardMath.allSets(in: board).first else { return XCTFail("7 distinct cards always hold a set") }
            table.collect(set)
        }
        XCTAssertGreaterThan(table.collectedCount, 63 * 3)
        XCTAssertFalse(table.isCleared)
    }

    func testOnlyTimeTrialsAreEndless() {
        XCTAssertEqual(GameMode.allCases.filter(\.hasEndlessDeck), [.timeTrialEasy, .timeTrialMedium, .timeTrialHard])
        XCTAssertTrue(DeckGame(mode: .timeTrialHard).table.isEndless)
        XCTAssertFalse(DeckGame(mode: .freePlay).table.isEndless)
    }

    func testTimeTrialBonuses() {
        XCTAssertEqual(GameMode.timeTrialEasy.timeTrial?.bonus, 15)
        XCTAssertEqual(GameMode.timeTrialMedium.timeTrial?.bonus, 10)
        XCTAssertEqual(GameMode.timeTrialHard.timeTrial?.bonus, 5)
        XCTAssertEqual(GameMode.timeTrialHard.timeTrial?.start, 20)
    }
}
