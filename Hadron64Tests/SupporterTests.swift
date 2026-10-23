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
        let s = Supporter(defaults: freshDefaults(), enforcesLimits: true)
        for _ in 0..<Supporter.freePlaysPerDay {
            XCTAssertTrue(s.allows(.remainder))
            s.recordPlay(.remainder)
        }
        XCTAssertFalse(s.allows(.remainder))
        XCTAssertTrue(s.isLocked(.remainder))
        XCTAssertTrue(s.allows(.game(.simple3)), "each mode has its own allowance")
    }

    func testMultiplayerAllowsOnePlayPerDay() {
        let s = Supporter(defaults: freshDefaults(), enforcesLimits: true)
        XCTAssertTrue(s.allows(.multiplayer(.freePlay)))
        s.recordPlay(.multiplayer(.freePlay))
        XCTAssertFalse(s.allows(.multiplayer(.freePlay)))
    }

    func testExtraHardAllowsOnePlayPerDay() {
        let s = Supporter(defaults: freshDefaults(), enforcesLimits: true)
        XCTAssertTrue(s.allows(.game(.extraHard)))
        s.recordPlay(.game(.extraHard))
        XCTAssertFalse(s.allows(.game(.extraHard)))
        XCTAssertTrue(s.allows(.game(.simple3)), "other training modes keep their own allowance")
    }

    func testMultiplayerInATrainingModeUsesBothAllowances() {
        let s = Supporter(defaults: freshDefaults(), enforcesLimits: true)
        s.recordPlay(.multiplayer(.extraHard))
        XCTAssertFalse(s.allows(.multiplayer(.freePlay)))
        XCTAssertFalse(s.allows(.game(.extraHard)))
        XCTAssertTrue(s.allows(.game(.extraHardTrialEasy)))
    }

    func testExtraHardTrialsGetExtraHardsAllowance() {
        let s = Supporter(defaults: freshDefaults(), enforcesLimits: true)
        XCTAssertTrue(s.allows(.game(.extraHardTrialHard)))
        s.recordPlay(.game(.extraHardTrialHard))
        XCTAssertFalse(s.allows(.game(.extraHardTrialHard)))
        XCTAssertTrue(s.allows(.game(.extraHardTrialEasy)), "each trial keeps its own count")
    }

    func testUnlimitedModesNeverLock() {
        let s = Supporter(defaults: freshDefaults(), enforcesLimits: true)
        for session in [Session.game(.freePlay), .game(.timeTrialHard), .tutorial] {
            for _ in 0..<10 { s.recordPlay(session) }
            XCTAssertTrue(s.allows(session))
        }
    }

    func testPlaysFromAnEarlierDayDontCount() {
        let d = freshDefaults()
        d.set(["remainder": 3], forKey: "trainingPlays")
        d.set(Calendar.current.date(byAdding: .day, value: -1, to: .now)!, forKey: "trainingPlaysDay")
        let s = Supporter(defaults: d, enforcesLimits: true)
        XCTAssertTrue(s.allows(.remainder))
        s.recordPlay(.remainder)
        XCTAssertTrue(s.allows(.remainder), "yesterday's plays were reset, so this is today's first")
    }

    func testDebugBuildsSkipLimitsByDefault() {
        let s = Supporter(defaults: freshDefaults())
        for _ in 0..<10 { s.recordPlay(.multiplayer(.freePlay)) }
        XCTAssertTrue(s.allows(.multiplayer(.freePlay)))
        XCTAssertFalse(s.isLocked(.remainder))
    }
}
