import AppKit
import Observation

/// The icon service has no icon to give for this address; asking again would not change that.
struct IconNotAvailable: Error {}

/// Loads website icons from the icon service the desktop app uses, and keeps them in memory only:
/// which websites the vault holds logins for is not written to disk.
@MainActor
@Observable
final class WebsiteIconStore {
    /// Throws `IconNotAvailable` when the service has no icon, and anything else when the request
    /// itself failed.
    typealias FetchIconData = @Sendable (URL) async throws -> Data

    /// Icons are small; anything larger is not one.
    private static let maxIconByteCount = 512 * 1024
    /// A request that failed on the way is tried once more when its row appears again.
    private static let maxNumAttempts = 2

    private var iconsByUrl = [URL: NSImage]()
    @ObservationIgnored private var fetchesInProgress = [URL: Task<Data, Error>]()
    @ObservationIgnored private var numAttemptsByUrl = [URL: Int]()
    /// Counts the calls of `forgetAll`, so that a fetch finishing after one does not bring an
    /// icon back.
    @ObservationIgnored private var numTimesForgotten = 0
    @ObservationIgnored private let fetchIconData: FetchIconData

    /// - Parameter fetchIconData: The network access, replaced in tests and in the demo.
    init(fetchIconData: @escaping FetchIconData = WebsiteIconStore.fetchOverNetwork) {
        self.fetchIconData = fetchIconData
    }

    func icon(at iconUrl: URL) -> NSImage? {
        iconsByUrl[iconUrl]
    }

    /// Fetches the icon unless it is there, on its way, or known not to be available.
    func loadIcon(at iconUrl: URL) async {
        let hasAttemptsLeft = (numAttemptsByUrl[iconUrl] ?? 0) < Self.maxNumAttempts
        guard iconsByUrl[iconUrl] == nil, fetchesInProgress[iconUrl] == nil, hasAttemptsLeft else {
            return
        }
        // Not a child of the caller's task: a row that scrolls away or is filtered out cancels
        // its task, and that must not be recorded as "this icon could not be fetched". The store
        // cancels the fetch itself when the icons are forgotten.
        let fetch = Task { [fetchIconData] in
            try await fetchIconData(iconUrl)
        }
        fetchesInProgress[iconUrl] = fetch
        let numTimesForgottenAtStart = numTimesForgotten
        let fetched = await fetch.result
        guard numTimesForgotten == numTimesForgottenAtStart else {
            return
        }
        fetchesInProgress[iconUrl] = nil

        if case .success(let iconData) = fetched, iconData.count <= Self.maxIconByteCount,
            let icon = NSImage(data: iconData), icon.isValid
        {
            iconsByUrl[iconUrl] = icon
        } else if case .failure(let failure) = fetched, !(failure is IconNotAvailable) {
            numAttemptsByUrl[iconUrl, default: 0] += 1
        } else {
            // No icon, or an answer that is not an image: final.
            numAttemptsByUrl[iconUrl] = Self.maxNumAttempts
        }
    }

    /// Called when the vault locks: the icons tell which websites are in it, and so would any
    /// request still on its way.
    func forgetAll() {
        for fetch in fetchesInProgress.values {
            fetch.cancel()
        }
        fetchesInProgress = [:]
        iconsByUrl = [:]
        numAttemptsByUrl = [:]
        numTimesForgotten += 1
    }

    /// A session that keeps nothing on disk: no cache, no cookies, no credentials.
    private nonisolated static let ephemeralSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }()

    nonisolated static func fetchOverNetwork(_ iconUrl: URL) async throws -> Data {
        let (iconData, response) = try await ephemeralSession.data(from: iconUrl)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw IconNotAvailable()
        }
        return iconData
    }
}
