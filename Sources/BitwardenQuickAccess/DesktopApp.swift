import AppKit
import QuickAccessCore

/// Where the installed Bitwarden desktop app keeps the things this app depends on.
enum DesktopApp {
    static let bundleIdentifier = "com.bitwarden.desktop"

    enum LocationError: Error {
        case desktopAppNotInstalled
        case stateFileNotFound
    }

    /// The helper inside the desktop app's bundle that relays messages to the running app.
    static func locateProxyExecutable() throws -> URL {
        guard let appBundle = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            throw LocationError.desktopAppNotInstalled
        }
        return appBundle.appending(path: "Contents/MacOS/desktop_proxy")
    }

    static func locateStateFile() throws -> URL {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        let candidates = [
            // The build downloaded from bitwarden.com.
            homeDirectory.appending(path: "Library/Application Support/Bitwarden/data.json"),
            // The Mac App Store build keeps its data in its sandbox container.
            homeDirectory.appending(
                path: "Library/Containers/\(bundleIdentifier)/Data/Library/Application Support/Bitwarden/data.json"
            ),
        ]
        guard let stateFile = candidates.first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            throw LocationError.stateFileNotFound
        }
        return stateFile
    }

    static func loadState() throws -> DesktopState {
        try DesktopState(stateFileContents: Data(contentsOf: locateStateFile()))
    }

    static func makeBiometricsClient() throws -> DesktopBiometricsClient {
        DesktopBiometricsClient(
            transport: try DesktopProxyTransport(proxyExecutable: locateProxyExecutable()),
            appId: ipcAppId
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
