import AppKit
import Observation
import QuickAccessCore

/// Holds the unlocked vault and decides when to drop it again.
///
/// The user key only ever lives in this object's memory. Unlocking asks the Bitwarden desktop app
/// for it; locking forgets it, following the desktop app's vault timeout setting.
@MainActor
@Observable
final class VaultSession {
    enum State {
        case locked(explanation: String?)
        case unlocking
        case unlocked(UnlockedVault)
    }

    private static let periodicCheckInterval: TimeInterval = 30

    private(set) var state = State.locked(explanation: nil)
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
                self?.handle(.systemWillSleep)
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
            let outcome = try await desktop.requestUnlock(userId: desktopState.userId)
            switch outcome {
            case .unlocked(let userKey):
                let vault = try VaultDecryptor.unlock(desktopState, userKey: userKey)
                self.userKey = userKey
                self.unlockedUserId = desktopState.userId
                self.stateFileModificationDate = stateFileModificationDate
                settings = desktopState.settings
                lastUseDate = currentDate()
                state = .unlocked(vault)
            case .denied:
                state = .locked(explanation: "Touch ID was cancelled.")
            case .unavailable(let status):
                state = .locked(explanation: Self.explain(status))
            }
        } catch {
            state = .locked(explanation: Self.explain(error))
        }
    }

    func lock() {
        userKey = nil
        unlockedUserId = nil
        state = .locked(explanation: nil)
        didLock()
    }

    /// Picks up what the desktop app has synced or changed since the vault was decrypted.
    func reloadIfDesktopStateChanged() {
        guard case .unlocked = state, let userKey else {
            return
        }
        do {
            let currentModificationDate = try desktop.readStateModificationDate()
            guard currentModificationDate != stateFileModificationDate else {
                return
            }
            let desktopState = try desktop.loadState()
            // A different account in the desktop app means this key is for the wrong vault.
            guard desktopState.userId == unlockedUserId else {
                lock()
                return
            }
            stateFileModificationDate = currentModificationDate
            settings = desktopState.settings
            state = .unlocked(try VaultDecryptor.unlock(desktopState, userKey: userKey))
        } catch {
            lock()
            state = .locked(explanation: Self.explain(error))
        }
    }

    /// Locks the vault if the vault timeout has passed. Runs periodically, and whenever the
    /// panel is about to use the vault.
    func enforceVaultTimeout() {
        handle(
            .periodicCheck(
                systemIdleSeconds: readSystemIdleSeconds(),
                secondsSinceLastUse: currentDate().timeIntervalSince(lastUseDate)
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

    private static func explain(_ status: BiometricsStatus) -> String {
        switch status {
        case .unlockNeeded:
            "Bitwarden needs your master password once after it starts. Unlock Bitwarden, then try again."
        case .notEnabledLocally, .notEnabledInConnectedDesktopApp:
            "Unlock with Touch ID is switched off in Bitwarden's settings."
        case .hardwareUnavailable:
            "Touch ID is not available right now."
        case .available, .autoSetupNeeded, .manualSetupNeeded, .platformUnsupported, .desktopDisconnected,
            .nativeMessagingPermissionMissing:
            "Bitwarden cannot unlock with Touch ID right now (\(status))."
        }
    }

    private static func explain(_ error: Error) -> String {
        switch error {
        case InstalledDesktopApp.LocationError.desktopAppNotInstalled:
            "The Bitwarden desktop app is not installed."
        case InstalledDesktopApp.LocationError.stateFileNotFound, DesktopStateError.noActiveAccount:
            "No account is logged in to the Bitwarden desktop app."
        case DesktopStateError.unsupportedAccountEncryption:
            "This account uses a newer encryption format that is not supported yet."
        case DesktopIpcError.noReply:
            "Bitwarden did not answer. Check that the desktop app is running."
        case DesktopIpcError.accountNotLoggedIntoDesktopApp:
            "The Bitwarden desktop app is logged in to a different account."
        case VaultError.userKeyDoesNotMatchAccount:
            "Bitwarden handed over a key for a different account. Try again."
        default:
            "Unlocking failed: \(error)"
        }
    }
}
