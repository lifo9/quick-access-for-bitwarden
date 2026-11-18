import AppKit
import ImageIO
import QuickAccessCore
import XCTest

@testable import QuickAccessForBitwarden

@MainActor
final class DemoTests: XCTestCase {
    func test_DemoDesktop__unlocksIntoAVaultWhoseUnprotectedValuesCanBeRead() async throws {
        let desktop = try DemoDesktop()
        let state = try desktop.loadState()
        guard case .unlocked(let userKey) = try await desktop.requestUnlock(userId: state.userId) else {
            return XCTFail("the demo vault did not unlock")
        }

        let vault = try VaultDecryptor.unlock(state, userKey: userKey)

        XCTAssertEqual(vault.numUndecryptableItems, 0)
        XCTAssertEqual(Set(vault.items.map(\.kind)), [.login, .secureNote, .card])
        XCTAssertFalse(vault.items.contains { $0.name.isEmpty })
        // What an item with master password re-prompt releases has a test of its own.
        for item in vault.items where !item.requiresMasterPasswordReprompt {
            for field in item.fields {
                XCTAssertNoThrow(try item.revealValue(of: field), "\(item.name): \(field.name)")
            }
            if let oneTimeCodeField = item.firstField(withRole: .oneTimeCode) {
                XCTAssertNoThrow(try TotpConfiguration(authenticatorKey: item.revealValue(of: oneTimeCodeField)))
            }
        }
        XCTAssertNotNil(state.settings.websiteIconServerUrl)
    }

    func test_DemoDesktop__hasAnItemThatKeepsItsSecretsBehindTheMasterPassword() async throws {
        let desktop = try DemoDesktop()
        let state = try desktop.loadState()
        guard case .unlocked(let userKey) = try await desktop.requestUnlock(userId: state.userId) else {
            return XCTFail("the demo vault did not unlock")
        }

        let vault = try VaultDecryptor.unlock(state, userKey: userKey)

        let protectedItem = try XCTUnwrap(vault.items.first(where: \.requiresMasterPasswordReprompt))
        for secretRole in [VaultFieldRole.password, .oneTimeCode] {
            let secretField = try XCTUnwrap(protectedItem.firstField(withRole: secretRole))
            XCTAssertThrowsError(try protectedItem.revealValue(of: secretField)) { thrownError in
                XCTAssertEqual(thrownError as? VaultError, .masterPasswordRepromptRequired)
            }
        }
        for listedRole in [VaultFieldRole.username, .website] {
            let listedField = try XCTUnwrap(protectedItem.firstField(withRole: listedRole))
            XCTAssertNoThrow(try protectedItem.revealValue(of: listedField))
        }
    }

    func test_DemoDesktop_requestUnlock__takesAsLongAsThePretendTouchIdPrompt() async throws {
        let desktop = try DemoDesktop(touchIdDuration: .milliseconds(200))
        let userId = try desktop.loadState().userId
        let clock = ContinuousClock()

        let unlockDuration = try await clock.measure {
            _ = try await desktop.requestUnlock(userId: userId)
        }

        XCTAssertGreaterThanOrEqual(unlockDuration, .milliseconds(200))
    }

    func test_DemoDesktop_chooseLanguage__makesTheStateNewerAndInThatLanguage() throws {
        let desktop = try DemoDesktop()
        let modificationDateBefore = try XCTUnwrap(desktop.readStateModificationDate())
        XCTAssertNil(try desktop.loadState().settings.desktopLocale)

        try desktop.chooseLanguage(desktopLocale: "sk")

        XCTAssertEqual(try desktop.loadState().settings.desktopLocale, "sk")
        XCTAssertGreaterThan(try XCTUnwrap(desktop.readStateModificationDate()), modificationDateBefore)
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

        // Every step of the script checks that the demo is where its caption says, so a script
        // that no longer matches the app fails here instead of recording something else.
        try await DemoRecorder.record(
            outputPathPrefix: outputDirectory.appending(path: "screencast").path,
            appIconPath: Self.repositoryRoot.appending(path: DemoRecorder.defaultAppIconPath).path
        )

        for appearance in ["dark", "light"] {
            let gifFile = outputDirectory.appending(path: "screencast-\(appearance).gif")
            let animation = try XCTUnwrap(CGImageSourceCreateWithURL(gifFile as CFURL, nil), "no \(appearance) file")
            XCTAssertGreaterThan(CGImageSourceGetCount(animation), 5)
        }
    }

    func test_DemoRecorder_record__failsWithoutTheAppIcon() async throws {
        let missingIconPath = "/nonexistent/AppIcon.icns"

        do {
            try await DemoRecorder.record(outputPathPrefix: "/nonexistent/screencast", appIconPath: missingIconPath)
            XCTFail("the recording did not fail")
        } catch DemoRecorder.RecordingError.appIconNotFound(let reportedPath) {
            XCTAssertEqual(reportedPath, missingIconPath)
        }
    }

    /// The tests may be run from any directory; the icon is found from where this file is.
    private static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}
