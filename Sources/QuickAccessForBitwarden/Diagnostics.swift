import Foundation
import QuickAccessCore

/// A command line check of every dependency on the Bitwarden desktop app, for when an update of
/// the desktop app changes its state file or its IPC. Prints counts and settings, never secrets.
@MainActor
enum Diagnostics {
    /// - Returns: The process exit status.
    static func run(includingUnlock: Bool) async -> Int32 {
        do {
            let desktop = InstalledDesktopApp()
            let state = try desktop.loadState()
            print("state file:        \(try desktop.locateStateFile().path)")
            print(
                "vault items:       \(state.ciphers.count) stored, \(state.organizationKeysByOrganizationId.count) organization keys"
            )
            print("vault timeout:     \(state.settings.vaultTimeout)")
            print("clipboard clear:   \(state.settings.clipboardClearDelay)")
            print(
                "biometric unlock:  \(state.settings.isBiometricUnlockEnabled ? "enabled" : "disabled") in the desktop app"
            )
            print("desktop proxy:     \(try desktop.locateProxyExecutable().path)")

            let status = try await desktop.requestBiometricsStatus(userId: state.userId)
            print("biometrics status: \(status)")

            guard includingUnlock else {
                return 0
            }
            print("requesting unlock: confirm the Touch ID prompt shown by Bitwarden")
            let outcome = try await desktop.requestUnlock(userId: state.userId)
            guard case .unlocked(let userKey) = outcome else {
                print("unlock outcome:    \(outcome)")
                return 1
            }
            report(try VaultDecryptor.unlock(state, userKey: userKey))
            return 0
        } catch {
            print("failed: \(error)")
            return 1
        }
    }

    private static func report(_ vault: UnlockedVault) {
        let numItemsByKind = Dictionary(grouping: vault.items, by: \.kind).mapValues(\.count)
        let fieldsWithItems = vault.items.flatMap { item in item.fields.map { (item, $0) } }
        let numRevealableFields = fieldsWithItems.count { item, field in (try? item.revealValue(of: field)) != nil }
        let oneTimeCodeFields = fieldsWithItems.filter { $0.1.role == .oneTimeCode }
        let numUsableOneTimeCodes = oneTimeCodeFields.count { item, field in
            (try? item.revealValue(of: field)).flatMap { try? TotpConfiguration(authenticatorKey: $0) } != nil
        }
        print("unlock outcome:    unlocked")
        print(
            "decrypted items:   \(vault.items.count) (\(numItemsByKind)), \(vault.numUndecryptableItems) undecryptable")
        print("fields:            \(numRevealableFields) of \(fieldsWithItems.count) can be revealed")
        print("one-time codes:    \(numUsableOneTimeCodes) of \(oneTimeCodeFields.count) can be generated")
        print("re-prompt items:   \(vault.items.count { $0.requiresMasterPasswordReprompt })")
    }
}
