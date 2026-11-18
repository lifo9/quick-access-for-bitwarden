import AppKit
import Observation

/// Loads website icons from the icon service the desktop app uses, and keeps them in memory only:
/// which websites the vault holds logins for is not written to disk.
@MainActor
@Observable
final class WebsiteIconStore {
    typealias FetchIconData = @Sendable (URL) async throws -> Data

    /// Icons are small; anything larger is not one.
    private static let maxIconByteCount = 512 * 1024

    private var iconsByUrl = [URL: NSImage]()
    @ObservationIgnored private var requestedIconUrls = Set<URL>()
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

    /// Fetches the icon unless that was tried before. A failed attempt is not repeated until the
    /// icons are forgotten, so a missing icon costs one request, not one per redraw.
    func loadIcon(at iconUrl: URL) async {
        guard requestedIconUrls.insert(iconUrl).inserted else {
            return
        }
        let numTimesForgottenAtStart = numTimesForgotten
        guard let iconData = try? await fetchIconData(iconUrl),
            iconData.count <= Self.maxIconByteCount,
            let icon = NSImage(data: iconData), icon.isValid,
            numTimesForgotten == numTimesForgottenAtStart
        else {
            return
        }
        iconsByUrl[iconUrl] = icon
    }

    /// Called when the vault locks: the icons tell which websites are in it.
    func forgetAll() {
        iconsByUrl = [:]
        requestedIconUrls = []
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
            throw URLError(.badServerResponse)
        }
        return iconData
    }
}
