import Foundation
import XCTest

@testable import QuickAccessCore

final class IdleTrackerTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    func test_idleSeconds__isTheSystemsIdleTimeWhileTheMacStaysAwake() {
        var tracker = IdleTracker()

        XCTAssertEqual(tracker.idleSeconds(at: start, systemIdleSeconds: 10), 10)
        XCTAssertEqual(tracker.idleSeconds(at: start + 30, systemIdleSeconds: 40), 40)
        XCTAssertEqual(tracker.idleSeconds(at: start + 60, systemIdleSeconds: 3), 3)
    }

    func test_systemDidWake__addsTheTimeAsleepToTheIdleTimeBeforeIt() {
        var tracker = IdleTracker()

        tracker.systemWillSleep(at: start, systemIdleSeconds: 60)

        XCTAssertEqual(tracker.systemDidWake(at: start + 3600), 3660)
    }

    func test_systemDidWake__accumulatesOverSleepsWithoutInputBetweenThem() {
        var tracker = IdleTracker()

        // Two idle minutes, two asleep, woken by the network for two more, asleep again.
        tracker.systemWillSleep(at: start, systemIdleSeconds: 120)
        XCTAssertEqual(tracker.systemDidWake(at: start + 120), 240)
        XCTAssertEqual(tracker.idleSeconds(at: start + 150, systemIdleSeconds: 150), 270)
        tracker.systemWillSleep(at: start + 240, systemIdleSeconds: 240)

        XCTAssertEqual(tracker.systemDidWake(at: start + 360), 480)
    }

    func test_idleSeconds__forgetsTheTimeAsleepOnceThereWasInput() {
        var tracker = IdleTracker()
        tracker.systemWillSleep(at: start, systemIdleSeconds: 60)
        _ = tracker.systemDidWake(at: start + 120)

        // The key press that woke the Mac: the system's idle time has started again.
        XCTAssertEqual(tracker.idleSeconds(at: start + 125, systemIdleSeconds: 2), 2)
        XCTAssertEqual(tracker.idleSeconds(at: start + 155, systemIdleSeconds: 32), 32)
    }

    func test_systemDidWake__countsNothingWithoutASleepBeforeIt() {
        var tracker = IdleTracker()
        _ = tracker.idleSeconds(at: start, systemIdleSeconds: 5)

        XCTAssertEqual(tracker.systemDidWake(at: start + 100), 5)
    }
}
