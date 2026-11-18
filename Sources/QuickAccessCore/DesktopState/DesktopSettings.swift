import Foundation

/// When the Bitwarden desktop app locks the vault, as stored in its "vault timeout" setting.
public enum VaultTimeout: Sendable, Equatable {
    case never
    case onRestart
    case onScreenLocked
    case onSleep
    case onSystemIdle
    case afterMinutes(Int)
    /// A value this app does not know. The lock policy treats it as the strictest setting.
    case unrecognized

    /// What the desktop app applies when the setting was never changed.
    public static let desktopDefault = VaultTimeout.onRestart

    init(storedText: String) {
        switch storedText {
        case "never": self = .never
        case "onRestart": self = .onRestart
        case "onLocked": self = .onScreenLocked
        case "onSleep": self = .onSleep
        case "onIdle": self = .onSystemIdle
        default:
            if let minutes = Int(storedText), minutes >= 0 {
                self = .afterMinutes(minutes)
            } else {
                self = .unrecognized
            }
        }
    }
}

/// How long a copied value may stay on the clipboard, as stored in the desktop app's
/// "clear clipboard" setting.
public enum ClipboardClearDelay: Sendable, Equatable {
    case never
    case seconds(Int)

    /// What the desktop app applies when the setting was never changed.
    public static let desktopDefault = ClipboardClearDelay.seconds(300)

    /// Used for a value this app does not know: short enough to be safe whatever was meant.
    static let fallbackForUnrecognizedValue = ClipboardClearDelay.seconds(30)

    init(storedText: String) {
        switch storedText {
        case "never": self = .never
        case "tenSeconds": self = .seconds(10)
        case "twentySeconds": self = .seconds(20)
        case "thirtySeconds": self = .seconds(30)
        case "oneMinute": self = .seconds(60)
        case "twoMinutes": self = .seconds(120)
        case "fiveMinutes": self = .seconds(300)
        default: self = Self.fallbackForUnrecognizedValue
        }
    }
}

/// The desktop app settings this app follows, so that both are configured in one place.
public struct DesktopSettings: Sendable, Equatable {
    public let vaultTimeout: VaultTimeout
    public let clipboardClearDelay: ClipboardClearDelay
    public let isBiometricUnlockEnabled: Bool
    /// The service website icons are fetched from; `nil` when "Show website icons" is switched
    /// off in the desktop app or the account's server is not known.
    public let websiteIconServerUrl: URL?
    /// The language the desktop app is set to, such as `sk` or `en-GB`; `nil` when it follows
    /// the system's language.
    public let desktopLocale: String?

    public init(
        vaultTimeout: VaultTimeout,
        clipboardClearDelay: ClipboardClearDelay,
        isBiometricUnlockEnabled: Bool,
        websiteIconServerUrl: URL? = nil,
        desktopLocale: String? = nil
    ) {
        self.vaultTimeout = vaultTimeout
        self.clipboardClearDelay = clipboardClearDelay
        self.isBiometricUnlockEnabled = isBiometricUnlockEnabled
        self.websiteIconServerUrl = websiteIconServerUrl
        self.desktopLocale = desktopLocale
    }
}
