import Foundation
import QuickAccessTestSupport
import XCTest

@testable import QuickAccessCore

final class WebsiteIconTests: XCTestCase {
    private let iconServerUrl = URL(string: "https://vault.example.com/icons")!

    private func iconUrl(forWebsite website: String) -> String? {
        WebsiteIcon.iconUrl(forWebsite: website, iconServerUrl: iconServerUrl)?.absoluteString
    }

    /// The icon service a state file with this environment and setting leads to.
    private func readIconServer(environment: [String: Any]?, showsIcons: Any? = nil) throws -> String? {
        let environmentSetting: [String: Any] =
            environment.map { [StateFileBuilder.settingKey("environment_environment"): $0] } ?? [:]
        let iconSetting: [String: Any] = showsIcons.map { ["global_domainSettings_showFavicons": $0] } ?? [:]
        let stateFile = try StateFileBuilder.makeStateFile(
            ciphers: [],
            settings: environmentSetting.merging(iconSetting) { first, _ in first }
        )
        return try DesktopState(stateFileContents: stateFile).settings.websiteIconServerUrl?.absoluteString
    }

    func test_iconUrl__addressesTheIconByTheWebsitesHostName() {
        XCTAssertEqual(
            iconUrl(forWebsite: "https://GitHub.com/login?next=1"),
            "https://vault.example.com/icons/github.com/icon.png")
        XCTAssertEqual(
            iconUrl(forWebsite: "http://shop.example.org:8443/"),
            "https://vault.example.com/icons/shop.example.org/icon.png")
    }

    func test_iconUrl__treatsAnAddressWithoutSchemeAsWebsite() {
        XCTAssertEqual(
            iconUrl(forWebsite: " example.com/account "), "https://vault.example.com/icons/example.com/icon.png")
    }

    func test_iconUrl__givesNoIconForAddressesThatAreNotWebsites() {
        for notAWebsite in [
            "androidapp://com.example.app", "iosapp://com.example", "ssh://host.example.com", "localhost", "",
        ] {
            XCTAssertNil(iconUrl(forWebsite: notAWebsite), "gave an icon for \(notAWebsite)")
        }
    }

    func test_iconUrl__neverNamesHiddenServicesToTheIconService() {
        XCTAssertNil(iconUrl(forWebsite: "http://exampleexampleexample.onion/login"))
        XCTAssertNil(iconUrl(forWebsite: "example.i2p"))
    }

    func test_DesktopState_init__findsTheIconServiceOfASelfHostedServer() throws {
        let selfHosted: [String: Any] = [
            "region": "Self-hosted",
            "urls": ["base": "https://vault.example.com/", "icons": NSNull(), "webVault": NSNull()],
        ]

        XCTAssertEqual(try readIconServer(environment: selfHosted), "https://vault.example.com/icons")
    }

    func test_DesktopState_init__prefersAnIconAddressSetExplicitly() throws {
        let selfHosted: [String: Any] = [
            "region": "Self-hosted",
            "urls": ["base": "https://vault.example.com", "icons": "https://icons.example.net"],
        ]

        XCTAssertEqual(try readIconServer(environment: selfHosted), "https://icons.example.net")
    }

    func test_DesktopState_init__usesTheCloudRegionsIconService() throws {
        XCTAssertEqual(
            try readIconServer(environment: ["region": "US", "urls": ["base": NSNull()]]), "https://icons.bitwarden.net"
        )
        XCTAssertEqual(try readIconServer(environment: ["region": "EU"]), "https://icons.bitwarden.eu")
    }

    func test_DesktopState_init__givesNoIconServiceWhenIconsAreSwitchedOffInTheDesktopApp() throws {
        XCTAssertNil(try readIconServer(environment: ["region": "EU"], showsIcons: false))
    }

    func test_DesktopState_init__readsAnIconSettingItDoesNotUnderstandAsOff() throws {
        // Only a setting that was never changed means "on"; guessing would name websites to
        // the icon service against a choice this app failed to read.
        XCTAssertNil(try readIconServer(environment: ["region": "EU"], showsIcons: "disabled"))
        XCTAssertNil(try readIconServer(environment: ["region": "EU"], showsIcons: ["value": false]))
        XCTAssertEqual(
            try readIconServer(environment: ["region": "EU"], showsIcons: NSNull()), "https://icons.bitwarden.eu")
    }

    func test_DesktopState_init__givesNoIconServiceWhenTheServerIsNotKnown() throws {
        XCTAssertNil(try readIconServer(environment: nil))
        XCTAssertNil(try readIconServer(environment: ["region": "Self-hosted", "urls": ["base": NSNull()]]))
        XCTAssertNil(try readIconServer(environment: ["region": "Elsewhere"]))
        // An environment in an unknown shape costs the icons, not the vault.
        XCTAssertNil(try readIconServer(environment: ["region": 7, "urls": "none"]))
    }
}
