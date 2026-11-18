import Foundation

/// Something that may require the vault to lock, depending on the vault timeout setting.
public enum LockEvent: Sendable, Equatable {
    case systemWillSleep
    case screenLocked
    /// A periodic check, carrying how long the user has not touched the Mac and how long ago this
    /// app was last used.
    case periodicCheck(systemIdleSeconds: TimeInterval, secondsSinceLastUse: TimeInterval)
}

/// Decides when this app drops the vault key, following the Bitwarden desktop app's vault timeout
/// setting so that both lock under the same conditions.
public enum LockPolicy {
    /// The idle time after which the desktop app considers the system idle.
    public static let systemIdleThresholdSeconds: TimeInterval = 5 * 60

    public static func shouldLock(vaultTimeout: VaultTimeout, on event: LockEvent) -> Bool {
        switch (vaultTimeout, event) {
        case (.never, _), (.onRestart, _):
            // Both keep the vault unlocked for as long as the app runs: the key only ever lives
            // in memory, so quitting the app is what locks it.
            false
        case (.onScreenLocked, .screenLocked), (.onSleep, .systemWillSleep):
            true
        case (.onScreenLocked, _), (.onSleep, _):
            false
        case (.onSystemIdle, .periodicCheck(let systemIdleSeconds, _)):
            systemIdleSeconds >= systemIdleThresholdSeconds
        case (.onSystemIdle, _):
            false
        case (.afterMinutes(let minutes), .periodicCheck(_, let secondsSinceLastUse)):
            secondsSinceLastUse >= TimeInterval(minutes) * 60
        case (.afterMinutes, _):
            false
        case (.unrecognized, .periodicCheck(let systemIdleSeconds, _)):
            // A setting this app cannot interpret gets the strictest reading of every event.
            systemIdleSeconds >= systemIdleThresholdSeconds
        case (.unrecognized, .screenLocked), (.unrecognized, .systemWillSleep):
            true
        }
    }
}
