import AppKit
import ImageIO
import QuickAccessCore
import XCTest

@testable import QuickAccessForBitwarden

@MainActor
final class DemoTests: XCTestCase {
    func test_DemoDesktop__unlocksIntoAVaultWhoseEveryValueCanBeRead() async throws {
        let desktop = try DemoDesktop()
        let state = try desktop.loadState()
        guard case .unlocked(let userKey) = try await desktop.requestUnlock(userId: state.userId) else {
            return XCTFail("the demo vault did not unlock")
        }

        let vault = try VaultDecryptor.unlock(state, userKey: userKey)

        XCTAssertEqual(vault.numUndecryptableItems, 0)
        XCTAssertEqual(Set(vault.items.map(\.kind)), [.login, .secureNote, .card])
        for item in vault.items {
            XCTAssertFalse(item.name.isEmpty)
            for field in item.fields {
                XCTAssertNoThrow(try item.revealValue(of: field), "\(item.name): \(field.name)")
            }
            if let oneTimeCodeField = item.firstField(withRole: .oneTimeCode) {
                XCTAssertNoThrow(try TotpConfiguration(authenticatorKey: item.revealValue(of: oneTimeCodeField)))
            }
        }
        XCTAssertNotNil(state.settings.websiteIconServerUrl)
    }

    func test_DemoIcons_makeIconData__drawsAnImageForAWebsite() async throws {
        let iconUrl = try XCTUnwrap(URL(string: "https://demo.invalid/icons/cloud.acme.example/icon.png"))

        let iconData = try await DemoIcons.makeIconData(for: iconUrl)

        XCTAssertEqual(NSImage(data: iconData)?.isValid, true)
    }

    func test_DemoRecorder_record__writesAnAnimationPerAppearance() async throws {
        let outputDirectory = FileManager.default.temporaryDirectory.appending(
            path: "demo-recording-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outputDirectory) }

        try await DemoRecorder.record(outputPathPrefix: outputDirectory.appending(path: "screencast").path)

        for appearance in ["dark", "light"] {
            let gifFile = outputDirectory.appending(path: "screencast-\(appearance).gif")
            let animation = try XCTUnwrap(CGImageSourceCreateWithURL(gifFile as CFURL, nil), "no \(appearance) file")
            XCTAssertGreaterThan(CGImageSourceGetCount(animation), 5)
        }
    }
}
