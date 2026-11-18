import AppKit
import QuickAccessCore

/// What this app needs from the Bitwarden desktop app. Everything that reaches out of the process
/// to the desktop app goes through here, which makes it the one place tests substitute.
@MainActor
protocol DesktopAccess {
    func loadState() throws -> DesktopState

    /// Changes whenever the desktop app writes its state, for example after a sync.
    func readStateModificationDate() throws -> Date?

    /// Shows the desktop app's Touch ID prompt, if biometric unlock is available for the account.
    func requestUnlock(userId: String) async throws -> BiometricUnlockOutcome
}

/// The Bitwarden desktop app installed on this Mac.
struct InstalledDesktopApp: DesktopAccess {
    static let bundleIdentifier = "com.bitwarden.desktop"

    enum LocationError: Error {
        case desktopAppNotInstalled
        case stateFileNotFound
    }

    private func locateAppBundle() throws -> URL {
        guard let appBundle = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleIdentifier) else {
            throw LocationError.desktopAppNotInstalled
        }
        return appBundle
    }

    /// The helper inside the desktop app's bundle that relays messages to the running app.
    func locateProxyExecutable() throws -> URL {
        try locateAppBundle().appending(path: "Contents/MacOS/desktop_proxy")
    }

    func locateStateFile() throws -> URL {
        // The Mac App Store build is sandboxed and keeps its data in its container; the build
        // from bitwarden.com does not. The installed build decides where to look: a file left
        // behind by the other build would be stale and belong to another session.
        let appStoreReceipt = try locateAppBundle().appending(path: "Contents/_MASReceipt/receipt")
        let isMacAppStoreBuild = FileManager.default.fileExists(atPath: appStoreReceipt.path)
        let stateFilePath =
            isMacAppStoreBuild
            ? "Library/Containers/\(Self.bundleIdentifier)/Data/Library/Application Support/Bitwarden/data.json"
            : "Library/Application Support/Bitwarden/data.json"
        let stateFile = FileManager.default.homeDirectoryForCurrentUser.appending(path: stateFilePath)
        guard FileManager.default.fileExists(atPath: stateFile.path) else {
            throw LocationError.stateFileNotFound
        }
        return stateFile
    }

    func loadState() throws -> DesktopState {
        try DesktopState(stateFileContents: Data(contentsOf: locateStateFile()))
    }

    func readStateModificationDate() throws -> Date? {
        try locateStateFile().resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    func requestUnlock(userId: String) async throws -> BiometricUnlockOutcome {
        try await makeBiometricsClient().requestUnlock(userId: userId)
    }

    func requestBiometricsStatus(userId: String) async throws -> BiometricsStatus {
        try await makeBiometricsClient().requestStatus(userId: userId)
    }

    private func makeBiometricsClient() throws -> DesktopBiometricsClient {
        DesktopBiometricsClient(
            transport: try DesktopProxyTransport(proxyExecutable: locateProxyExecutable()),
            appId: Self.ipcAppId
        )
    }

    /// The desktop app tells its IPC clients apart by an id each client picks for itself.
    private static var ipcAppId: String {
        let defaultsKey = "desktopIpcAppId"
        if let storedAppId = UserDefaults.standard.string(forKey: defaultsKey) {
            return storedAppId
        }
        let newAppId = UUID().uuidString.lowercased()
        UserDefaults.standard.set(newAppId, forKey: defaultsKey)
        return newAppId
    }
}
