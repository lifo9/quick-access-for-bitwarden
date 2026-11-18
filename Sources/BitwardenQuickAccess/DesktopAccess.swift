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

    /// The helper inside the desktop app's bundle that relays messages to the running app.
    func locateProxyExecutable() throws -> URL {
        guard let appBundle = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleIdentifier) else {
            throw LocationError.desktopAppNotInstalled
        }
        return appBundle.appending(path: "Contents/MacOS/desktop_proxy")
    }

    func locateStateFile() throws -> URL {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            // The build downloaded from bitwarden.com.
            homeDirectory.appending(path: "Library/Application Support/Bitwarden/data.json"),
            // The Mac App Store build keeps its data in its sandbox container.
            homeDirectory.appending(
                path: "Library/Containers/\(Self.bundleIdentifier)/Data/Library/Application Support/Bitwarden/data.json"
            ),
        ]
        guard let stateFile = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
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
