import Foundation
import Testing

@testable import AnchorCore

@Suite("Time accounting")
struct TimeAccountTests {
    let start = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("Elapsed time comes from the wall clock, so it survives relaunch")
    func elapsedTracksWallClock() {
        let account = TimeAccount(plannedSeconds: 1500, runningSince: start)
        #expect(account.elapsed(at: start) == 0)
        #expect(account.elapsed(at: start.addingTimeInterval(300)) == 300)
        // The app being closed for an hour changes nothing: the interval is open.
        #expect(account.elapsed(at: start.addingTimeInterval(3600)) == 3600)
    }

    @Test("Paused time is excluded")
    func pauseExcludesTime() {
        var account = TimeAccount(plannedSeconds: 1500, runningSince: start)
        account.pause(at: start.addingTimeInterval(120))
        #expect(account.bankedSeconds == 120)
        #expect(!account.isRunning)

        // Ten minutes pass while paused.
        let resumeAt = start.addingTimeInterval(720)
        #expect(account.elapsed(at: resumeAt) == 120)

        account.resume(at: resumeAt)
        #expect(account.elapsed(at: resumeAt.addingTimeInterval(60)) == 180)
    }

    @Test("Pause and resume are idempotent")
    func transitionsAreIdempotent() {
        var account = TimeAccount(plannedSeconds: 600, runningSince: start)
        account.pause(at: start.addingTimeInterval(60))
        account.pause(at: start.addingTimeInterval(300))
        #expect(account.bankedSeconds == 60)

        account.resume(at: start.addingTimeInterval(300))
        account.resume(at: start.addingTimeInterval(400))
        // The second resume must not restart the interval.
        #expect(account.elapsed(at: start.addingTimeInterval(400)) == 160)
    }

    @Test("Remaining never goes negative and the plan is met exactly on time")
    func remainingClamps() {
        let account = TimeAccount(plannedSeconds: 60, runningSince: start)
        #expect(account.remaining(at: start.addingTimeInterval(30)) == 30)
        #expect(account.remaining(at: start.addingTimeInterval(60)) == 0)
        #expect(account.remaining(at: start.addingTimeInterval(600)) == 0)
        #expect(!account.hasMetPlan(at: start.addingTimeInterval(59)))
        #expect(account.hasMetPlan(at: start.addingTimeInterval(60)))
    }

    @Test("A backwards clock cannot rewind earned time")
    func backwardsClockIsSafe() {
        // NTP corrections and manual clock changes are real; without the guard
        // this would report a negative interval and the ring would jump back.
        let account = TimeAccount(plannedSeconds: 600, bankedSeconds: 100, runningSince: start)
        #expect(account.elapsed(at: start.addingTimeInterval(-500)) == 100)
    }

    @Test("Fraction stays inside 0...1")
    func fractionClamps() {
        let account = TimeAccount(plannedSeconds: 100, runningSince: start)
        #expect(account.fraction(at: start) == 0)
        #expect(account.fraction(at: start.addingTimeInterval(50)) == 0.5)
        #expect(account.fraction(at: start.addingTimeInterval(500)) == 1)
    }

    @Test("Open-ended sessions report elapsed only")
    func openEndedBehaviour() {
        let account = TimeAccount(plannedSeconds: 0, runningSince: start)
        #expect(account.isOpenEnded)
        #expect(account.remaining(at: start.addingTimeInterval(900)) == 0)
        #expect(account.fraction(at: start.addingTimeInterval(900)) == 0)
        #expect(!account.hasMetPlan(at: start.addingTimeInterval(900)))
        #expect(account.elapsed(at: start.addingTimeInterval(900)) == 900)
    }

    @Test("Extending pushes the finish line without touching earned time")
    func extendKeepsElapsed() {
        var account = TimeAccount(plannedSeconds: 300, runningSince: start)
        account.extend(by: 300)
        #expect(account.plannedSeconds == 600)
        #expect(account.elapsed(at: start.addingTimeInterval(300)) == 300)
        #expect(account.remaining(at: start.addingTimeInterval(300)) == 300)
    }

    @Test("Extending an open-ended session does nothing")
    func extendIgnoresOpenEnded() {
        var account = TimeAccount(plannedSeconds: 0, runningSince: start)
        account.extend(by: 600)
        #expect(account.isOpenEnded)
    }
}
