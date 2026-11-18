import Foundation

/// The account's server environment as the desktop app stores it, reduced to what decides where
/// website icons come from.
struct StoredEnvironment: Decodable {
    struct Urls: Decodable {
        let base: String?
        let icons: String?
        let webVault: String?
    }

    let region: String?
    let urls: Urls?
}

/// Website icons, as the desktop app shows them next to logins: fetched from an icon service by
/// the website's host name.
public enum WebsiteIcon {
    /// The icon services of Bitwarden's own cloud, by the name the desktop app stores for the
    /// region.
    private static let cloudIconServersByRegion = [
        "US": "https://icons.bitwarden.net",
        "EU": "https://icons.bitwarden.eu",
    ]

    /// The icon service of the account's server, by the desktop app's rule: an icon address set
    /// explicitly, else `/icons` on the server's base or web vault address, else the cloud
    /// region's service.
    ///
    /// Unlike the desktop app, an environment that names no server gives no icon service instead
    /// of Bitwarden's cloud: asking a service about the websites in a vault is not something to
    /// do on a guess.
    static func resolveIconServerUrl(environment: StoredEnvironment?) -> URL? {
        guard let environment else {
            return nil
        }
        let addressesOnOwnServer = [
            environment.urls?.icons,
            environment.urls?.base.map { trimTrailingSlashes($0) + "/icons" },
            environment.urls?.webVault.map { trimTrailingSlashes($0) + "/icons" },
        ]
        let iconServerAddress =
            addressesOnOwnServer.compactMap { $0 }.first { !$0.isEmpty }
            ?? environment.region.flatMap { cloudIconServersByRegion[$0] }
        guard let iconServerAddress, let iconServerUrl = URL(string: trimTrailingSlashes(iconServerAddress)),
            ["http", "https"].contains(iconServerUrl.scheme?.lowercased() ?? "")
        else {
            return nil
        }
        return iconServerUrl
    }

    /// The address of the icon the desktop app shows for a login with this website, or `nil`
    /// where it shows its generic symbol: for addresses that are not websites, and for hidden
    /// services, whose names must not be sent anywhere.
    public static func iconUrl(forWebsite website: String, iconServerUrl: URL) -> URL? {
        let trimmedWebsite = website.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercasedWebsite = trimmedWebsite.lowercased()
        guard lowercasedWebsite.contains(".") else {
            return nil
        }
        let websiteAddress: String
        if !lowercasedWebsite.contains("://") {
            websiteAddress = "http://" + trimmedWebsite
        } else if lowercasedWebsite.hasPrefix("http://") || lowercasedWebsite.hasPrefix("https://") {
            websiteAddress = trimmedWebsite
        } else {
            return nil
        }
        guard let hostName = URLComponents(string: websiteAddress)?.host?.lowercased(), !hostName.isEmpty,
            !hostName.hasSuffix(".onion"), !hostName.hasSuffix(".i2p")
        else {
            return nil
        }
        return iconServerUrl.appending(path: hostName).appending(path: "icon.png")
    }

    private static func trimTrailingSlashes(_ address: String) -> String {
        String(address.reversed().drop { $0 == "/" }.reversed())
    }
}
