import XCTest
@testable import Hadron64

@MainActor
final class SupporterTests: XCTestCase {
    private func freshDefaults(_ name: String = #function) -> UserDefaults {
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func testTrainingModesAllowThreePlaysEachPerDay() {
        let s = Supporter(defaults: freshDefaults())
        for _ in 0..<Supporter.freePlaysPerDay {
            XCTAssertTrue(s.allows(.remainder))
            s.recordPlay(.remainder)
        }
        XCTAssertFalse(s.allows(.remainder))
        XCTAssertTrue(s.isLocked(.remainder))
        XCTAssertTrue(s.allows(.setSize), "each mode has its own allowance")
        XCTAssertTrue(s.allows(.game(.simple3)))
    }

    func testMultiplayerAllowsOnePlayPerDay() {
        let s = Supporter(defaults: freshDefaults())
        XCTAssertTrue(s.allows(.multiplayer))
        s.recordPlay(.multiplayer)
        XCTAssertFalse(s.allows(.multiplayer))
    }

    func testUnlimitedModesNeverLock() {
        let s = Supporter(defaults: freshDefaults())
        for session in [Session.game(.freePlay), .game(.timeTrialHard), .tutorial] {
            for _ in 0..<10 { s.recordPlay(session) }
            XCTAssertTrue(s.allows(session))
        }
    }

    func testPlaysFromAnEarlierDayDontCount() {
        let d = freshDefaults()
        d.set(["remainder": 3], forKey: "trainingPlays")
        d.set(Calendar.current.date(byAdding: .day, value: -1, to: .now)!, forKey: "trainingPlaysDay")
        let s = Supporter(defaults: d)
        XCTAssertTrue(s.allows(.remainder))
        s.recordPlay(.remainder)
        XCTAssertTrue(s.allows(.remainder), "yesterday's plays were reset, so this is today's first")
    }
}
