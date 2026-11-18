import Foundation
import XCTest

@testable import QuickAccessCore

final class LockPolicyTests: XCTestCase {
    private func check(systemIdleSeconds: TimeInterval = 0, secondsSinceLastUse: TimeInterval = 0) -> LockEvent {
        .periodicCheck(systemIdleSeconds: systemIdleSeconds, secondsSinceLastUse: secondsSinceLastUse)
    }

    func test_shouldLock__onSystemIdleLocksAfterFiveIdleMinutesOnly() {
        XCTAssertFalse(LockPolicy.shouldLock(vaultTimeout: .onSystemIdle, on: check(systemIdleSeconds: 299)))
        XCTAssertTrue(LockPolicy.shouldLock(vaultTimeout: .onSystemIdle, on: check(systemIdleSeconds: 300)))
        XCTAssertFalse(LockPolicy.shouldLock(vaultTimeout: .onSystemIdle, on: .systemWillSleep))
        XCTAssertFalse(LockPolicy.shouldLock(vaultTimeout: .onSystemIdle, on: .screenLocked))
    }

    func test_shouldLock__afterMinutesCountsFromLastUseOfThisApp() {
        let timeout = VaultTimeout.afterMinutes(15)

        XCTAssertFalse(
            LockPolicy.shouldLock(vaultTimeout: timeout, on: check(systemIdleSeconds: 3600, secondsSinceLastUse: 899)))
        XCTAssertTrue(LockPolicy.shouldLock(vaultTimeout: timeout, on: check(secondsSinceLastUse: 900)))
        XCTAssertTrue(LockPolicy.shouldLock(vaultTimeout: .afterMinutes(0), on: check()))
    }

    func test_shouldLock__onSleepAndOnScreenLockedReactToTheirEventOnly() {
        XCTAssertTrue(LockPolicy.shouldLock(vaultTimeout: .onSleep, on: .systemWillSleep))
        XCTAssertFalse(LockPolicy.shouldLock(vaultTimeout: .onSleep, on: .screenLocked))
        XCTAssertTrue(LockPolicy.shouldLock(vaultTimeout: .onScreenLocked, on: .screenLocked))
        XCTAssertFalse(LockPolicy.shouldLock(vaultTimeout: .onScreenLocked, on: check(systemIdleSeconds: 3600)))
    }

    func test_shouldLock__neverAndOnRestartKeepTheVaultUnlockedWhileRunning() {
        for timeout in [VaultTimeout.never, .onRestart] {
            for event in [
                LockEvent.systemWillSleep, .screenLocked, check(systemIdleSeconds: 86400, secondsSinceLastUse: 86400),
            ] {
                XCTAssertFalse(LockPolicy.shouldLock(vaultTimeout: timeout, on: event))
            }
        }
    }

    func test_shouldLock__unrecognizedSettingLocksOnEveryEvent() {
        XCTAssertTrue(LockPolicy.shouldLock(vaultTimeout: .unrecognized, on: .systemWillSleep))
        XCTAssertTrue(LockPolicy.shouldLock(vaultTimeout: .unrecognized, on: .screenLocked))
        XCTAssertTrue(LockPolicy.shouldLock(vaultTimeout: .unrecognized, on: check(systemIdleSeconds: 300)))
    }
}
