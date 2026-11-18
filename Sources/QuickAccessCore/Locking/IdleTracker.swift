import Foundation

/// How long the Mac has gone without input, counting the time it was asleep.
///
/// The system's own idle time stands still while the Mac sleeps and starts again with the key
/// press that wakes it. Taken alone it says "used a moment ago" after a night of sleep, so a
/// vault that locks when the system is idle would stay open. This keeps the missing part: the
/// time asleep since the last input, across any number of sleeps.
public struct IdleTracker: Sendable {
    /// Allows for the imprecision of two clocks read a moment apart.
    private static let toleranceSeconds: TimeInterval = 1

    private var previousCheck: (date: Date, systemIdleSeconds: TimeInterval)?
    private var sleepStartDate: Date?
    private var secondsAsleepSinceLastInput: TimeInterval = 0
    private var secondsAsleepSincePreviousCheck: TimeInterval = 0

    public init() {}

    /// The time without input as of now, to be asked regularly and before every use of the vault.
    ///
    /// - Parameter systemIdleSeconds: The system's idle time, which leaves out time asleep.
    public mutating func idleSeconds(at now: Date, systemIdleSeconds: TimeInterval) -> TimeInterval {
        if let previousCheck {
            let secondsAwakeSincePreviousCheck =
                now.timeIntervalSince(previousCheck.date) - secondsAsleepSincePreviousCheck
            // Without input the system's idle time grows by exactly the time awake; anything
            // less means there was input, and the time asleep before it no longer counts.
            let idleSecondsExpectedWithoutInput = previousCheck.systemIdleSeconds + secondsAwakeSincePreviousCheck
            if systemIdleSeconds < idleSecondsExpectedWithoutInput - Self.toleranceSeconds {
                secondsAsleepSinceLastInput = 0
            }
        }
        previousCheck = (now, systemIdleSeconds)
        secondsAsleepSincePreviousCheck = 0
        return systemIdleSeconds + secondsAsleepSinceLastInput
    }

    public mutating func systemWillSleep(at now: Date, systemIdleSeconds: TimeInterval) {
        _ = idleSeconds(at: now, systemIdleSeconds: systemIdleSeconds)
        sleepStartDate = now
    }

    /// - Returns: The time without input as of the moment of waking: what the idle time was
    ///   when the Mac went to sleep, plus all the time asleep since the last input. Whatever
    ///   woke the Mac, a key press included, is not part of it yet.
    public mutating func systemDidWake(at now: Date) -> TimeInterval {
        if let sleepStartDate {
            let secondsAsleep = max(0, now.timeIntervalSince(sleepStartDate))
            secondsAsleepSinceLastInput += secondsAsleep
            secondsAsleepSincePreviousCheck += secondsAsleep
            self.sleepStartDate = nil
        }
        return (previousCheck?.systemIdleSeconds ?? 0) + secondsAsleepSinceLastInput
    }
}
