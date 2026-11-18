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

    private let desktop: any DesktopAccess
    private var userKey: SymmetricCryptoKey?
    private var unlockedUserId: String?
    private var stateFileModificationDate: Date?
    private var lastUseDate = Date()
    private var periodicCheck: Timer?

    init(desktop: any DesktopAccess) {
        self.desktop = desktop
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
        periodicCheck = Timer.scheduledTimer(withTimeInterval: Self.periodicCheckInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.runPeriodicCheck()
            }
        }
    }

    var isUnlocked: Bool {
        if case .unlocked = state { true } else { false }
    }

    func noteUse() {
        lastUseDate = Date()
    }

    func unlock() async {
        guard case .locked = state else {
            return
        }
        state = .unlocking
        do {
            let desktopState = try desktop.loadState()
            let stateFileModificationDate = try desktop.readStateModificationDate()
            let outcome = try await desktop.requestUnlock(userId: desktopState.userId)
            switch outcome {
            case let .unlocked(userKey):
                let vault = try VaultDecryptor.unlock(desktopState, userKey: userKey)
                self.userKey = userKey
                self.unlockedUserId = desktopState.userId
                self.stateFileModificationDate = stateFileModificationDate
                settings = desktopState.settings
                lastUseDate = Date()
                state = .unlocked(vault)
            case .denied:
                state = .locked(explanation: "Touch ID was cancelled.")
            case let .unavailable(status):
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

    private func runPeriodicCheck() {
        // Any kind of input counts as activity, as it does for the desktop app's idle check.
        let anyInputEventType = CGEventType(rawValue: UInt32.max)!
        let systemIdleSeconds = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInputEventType)
        handle(.periodicCheck(
            systemIdleSeconds: systemIdleSeconds,
            secondsSinceLastUse: Date().timeIntervalSince(lastUseDate)
        ))
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
