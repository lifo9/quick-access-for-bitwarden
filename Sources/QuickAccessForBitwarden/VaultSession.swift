import AppKit
import Observation
import QuickAccessCore

/// Why the vault stayed locked, for the panel to say in the user's language.
enum UnlockFailure: Equatable {
    case touchIdWasCancelled
    case masterPasswordNeededFirst
    case touchIdSwitchedOffInBitwarden
    case touchIdNotAvailable
    /// The desktop app's status, by its number, which is what a report of the problem needs.
    case cannotUnlockWithTouchId(statusCode: Int)
    case desktopAppNotInstalled
    case noAccountLoggedIn
    case unsupportedAccountEncryption
    case desktopAppDidNotAnswer
    case desktopAppUsesAnotherAccount
    case keyOfAnotherAccount
    case other(description: String)

    init(_ status: BiometricsStatus) {
        switch status {
        case .unlockNeeded:
            self = .masterPasswordNeededFirst
        case .notEnabledLocally, .notEnabledInConnectedDesktopApp:
            self = .touchIdSwitchedOffInBitwarden
        case .hardwareUnavailable:
            self = .touchIdNotAvailable
        case .available, .autoSetupNeeded, .manualSetupNeeded, .platformUnsupported, .desktopDisconnected,
            .nativeMessagingPermissionMissing:
            self = .cannotUnlockWithTouchId(statusCode: status.rawValue)
        }
    }

    init(_ error: Error) {
        switch error {
        case InstalledDesktopApp.LocationError.desktopAppNotInstalled:
            self = .desktopAppNotInstalled
        case InstalledDesktopApp.LocationError.stateFileNotFound, DesktopStateError.noActiveAccount:
            self = .noAccountLoggedIn
        case DesktopStateError.unsupportedAccountEncryption:
            self = .unsupportedAccountEncryption
        case DesktopIpcError.noReply:
            self = .desktopAppDidNotAnswer
        case DesktopIpcError.accountNotLoggedIntoDesktopApp:
            self = .desktopAppUsesAnotherAccount
        case VaultError.userKeyDoesNotMatchAccount:
            self = .keyOfAnotherAccount
        default:
            self = .other(description: "\(error)")
        }
    }
}

/// Holds the unlocked vault and decides when to drop it again.
///
/// The user key only ever lives in this object's memory. Unlocking asks the Bitwarden desktop app
/// for it; locking forgets it, following the desktop app's vault timeout setting.
@MainActor
@Observable
final class VaultSession {
    enum State {
        case locked(failure: UnlockFailure?)
        case unlocking
        case unlocked(UnlockedVault)
    }

    private static let periodicCheckInterval: TimeInterval = 30

    private(set) var state = State.locked(failure: nil)
    private(set) var settings = DesktopSettings(
        vaultTimeout: VaultTimeout.desktopDefault,
        clipboardClearDelay: ClipboardClearDelay.desktopDefault,
        isBiometricUnlockEnabled: false
    )

    /// Called after the vault was locked, whatever locked it.
    var didLock: () -> Void = {}

    private let desktop: any DesktopAccess
    private let currentDate: () -> Date
    private let readSystemIdleSeconds: () -> TimeInterval
    private var userKey: SymmetricCryptoKey?
    private var unlockedUserId: String?
    private var stateFileModificationDate: Date?
    private var lastUseDate: Date
    private var idleTracker = IdleTracker()
    private var periodicCheck: Timer?

    /// - Parameters:
    ///   - currentDate: The clock, replaced in tests.
    ///   - readSystemIdleSeconds: How long the Mac has had no input, replaced in tests.
    init(
        desktop: any DesktopAccess,
        currentDate: @escaping () -> Date = { Date() },
        readSystemIdleSeconds: @escaping () -> TimeInterval = VaultSession.readSystemIdleSeconds
    ) {
        self.desktop = desktop
        self.currentDate = currentDate
        self.readSystemIdleSeconds = readSystemIdleSeconds
        lastUseDate = currentDate()
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.systemWillSleep()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.systemDidWake()
            }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handle(.screenLocked)
            }
        }
        periodicCheck = Timer.scheduledTimer(withTimeInterval: Self.periodicCheckInterval, repeats: true) {
            [weak self] _ in
            MainActor.assumeIsolated {
                self?.enforceVaultTimeout()
            }
        }
    }

    var isUnlocked: Bool {
        if case .unlocked = state { true } else { false }
    }

    func noteUse() {
        lastUseDate = currentDate()
    }

    func unlock() async {
        guard case .locked = state else {
            return
        }
        state = .unlocking
        do {
            // Noted before the contents are read: a write by the desktop app in between then
            // shows up as a change at the next reload instead of counting as already seen.
            let stateFileModificationDate = try desktop.readStateModificationDate()
            let desktopState = try desktop.loadState()
            // The settings hold whether or not the unlock succeeds: a refusal is explained in
            // the language they name.
            self.stateFileModificationDate = stateFileModificationDate
            settings = desktopState.settings
            let outcome = try await desktop.requestUnlock(userId: desktopState.userId)
            switch outcome {
            case .unlocked(let userKey):
                let vault = try VaultDecryptor.unlock(desktopState, userKey: userKey)
                self.userKey = userKey
                self.unlockedUserId = desktopState.userId
                lastUseDate = currentDate()
                state = .unlocked(vault)
            case .denied:
                state = .locked(failure: .touchIdWasCancelled)
            case .unavailable(let status):
                state = .locked(failure: UnlockFailure(status))
            }
        } catch {
            state = .locked(failure: UnlockFailure(error))
        }
    }

    func lock() {
        userKey = nil
        unlockedUserId = nil
        state = .locked(failure: nil)
        didLock()
    }

    /// Picks up what the desktop app has synced or changed: its settings always, which decide
    /// among other things the language of the panel, and the vault when it is unlocked here.
    func reloadIfDesktopStateChanged() {
        // An unlock under way has read the state and will decrypt exactly what it read. Marking
        // a newer state as seen now would hide it from the reload after the unlock.
        if case .unlocking = state {
            return
        }
        do {
            let currentModificationDate = try desktop.readStateModificationDate()
            guard currentModificationDate != stateFileModificationDate else {
                return
            }
            // Recorded before the attempt: a state that cannot be read is not read again and
            // again, only once it has changed.
            stateFileModificationDate = currentModificationDate
            let desktopState = try desktop.loadState()
            settings = desktopState.settings
            guard case .unlocked = state, let userKey else {
                return
            }
            // A different account in the desktop app means this key is for the wrong vault.
            guard desktopState.userId == unlockedUserId else {
                lock()
                return
            }
            state = .unlocked(try VaultDecryptor.unlock(desktopState, userKey: userKey))
        } catch {
            // While locked there is nothing to drop; unlocking reads the state again and says
            // what is wrong with it.
            if isUnlocked {
                lock()
                state = .locked(failure: UnlockFailure(error))
            }
        }
    }

    func systemWillSleep() {
        idleTracker.systemWillSleep(at: currentDate(), systemIdleSeconds: readSystemIdleSeconds())
        handle(.systemWillSleep)
    }

    /// No periodic check runs while the Mac sleeps, and the key press that wakes it resets the
    /// system's idle time, so the idle time is judged here as it stood at the moment of waking.
    func systemDidWake() {
        let now = currentDate()
        handle(
            .periodicCheck(
                systemIdleSeconds: idleTracker.systemDidWake(at: now),
                secondsSinceLastUse: now.timeIntervalSince(lastUseDate)
            ))
    }

    /// Locks the vault if the vault timeout has passed. Runs periodically, and whenever the
    /// panel is about to use the vault.
    func enforceVaultTimeout() {
        let now = currentDate()
        handle(
            .periodicCheck(
                systemIdleSeconds: idleTracker.idleSeconds(at: now, systemIdleSeconds: readSystemIdleSeconds()),
                secondsSinceLastUse: now.timeIntervalSince(lastUseDate)
            ))
    }

    nonisolated static func readSystemIdleSeconds() -> TimeInterval {
        // Any kind of input counts as activity, as it does for the desktop app's idle check.
        let anyInputEventType = CGEventType(rawValue: UInt32.max)!
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInputEventType)
    }

    /// Locks the vault if the desktop app's vault timeout setting asks for it on this event.
    func handle(_ event: LockEvent) {
        guard isUnlocked, LockPolicy.shouldLock(vaultTimeout: settings.vaultTimeout, on: event) else {
            return
        }
        lock()
    }
}
