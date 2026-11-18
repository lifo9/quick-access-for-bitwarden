import AppKit
import QuickAccessCore
import QuickAccessTestSupport
import XCTest

@testable import QuickAccessForBitwarden

/// Stands in for the Bitwarden desktop app: serves a state file and answers unlock requests.
@MainActor
private final class FakeDesktop: DesktopAccess {
    var stateFile: Data
    var stateModificationDate = Date(timeIntervalSince1970: 1_000)
    var unlockOutcome = BiometricUnlockOutcome.unlocked(Fixtures.userKey)
    private(set) var numUnlockRequests = 0

    init(stateFile: Data) {
        self.stateFile = stateFile
    }

    /// Runs right after the state file was read, to play a write by the desktop app.
    var afterLoadState: () -> Void = {}

    func loadState() throws -> DesktopState {
        defer { afterLoadState() }
        return try DesktopState(stateFileContents: stateFile)
    }

    func readStateModificationDate() throws -> Date? {
        stateModificationDate
    }

    func requestUnlock(userId: String) async throws -> BiometricUnlockOutcome {
        numUnlockRequests += 1
        return unlockOutcome
    }
}

/// Stands in for the icon service: answers every request with the same small image, or fails.
private final class FakeIconService: @unchecked Sendable {
    private let lock = NSLock()
    private var urls = [URL]()
    private var data: Data? = FakeIconService.makeImageData()

    var requestedUrls: [URL] {
        lock.withLock { urls }
    }

    /// `nil` makes every request fail.
    func setResponseData(_ responseData: Data?) {
        lock.withLock { data = responseData }
    }

    func fetch(_ iconUrl: URL) async throws -> Data {
        // Like a network request, this fails when the task it runs in was cancelled.
        try Task.checkCancellation()
        let responseData = lock.withLock {
            urls.append(iconUrl)
            return data
        }
        guard let responseData else {
            throw URLError(.badServerResponse)
        }
        return responseData
    }

    static func makeImageData() -> Data {
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        return bitmap.representation(using: .png, properties: [:])!
    }
}

/// Records what the model asks of the app around it.
@MainActor
private final class EffectRecorder {
    var openedUrls = [URL]()
    var numDismissals = 0
    var numKeyboardFocusRequests = 0
}

/// The time and the idle time the session sees.
@MainActor
private final class TestClock {
    var now = Date(timeIntervalSince1970: 1_000_000)
    var systemIdleSeconds: TimeInterval = 0

    func advance(bySeconds seconds: TimeInterval) {
        now += seconds
    }
}

/// The model wired to a fake desktop app, a private pasteboard and private preferences.
@MainActor
private final class Harness {
    let desktop: FakeDesktop
    let pasteboard = NSPasteboard.withUniqueName()
    let session: VaultSession
    let model: QuickAccessModel
    let clock = TestClock()
    let iconService = FakeIconService()
    private let effects = EffectRecorder()
    private let defaultsSuiteName = "QuickAccessModelTests-\(UUID().uuidString)"

    init(ciphers: [[String: Any]], settings: [String: Any] = [:]) throws {
        desktop = FakeDesktop(stateFile: try StateFileBuilder.makeStateFile(ciphers: ciphers, settings: settings))
        session = VaultSession(
            desktop: desktop,
            currentDate: { [clock] in clock.now },
            readSystemIdleSeconds: { [clock] in clock.systemIdleSeconds }
        )
        model = QuickAccessModel(
            session: session,
            iconStore: WebsiteIconStore(fetchIconData: iconService.fetch),
            clipboard: ClipboardWriter(pasteboard: pasteboard),
            usageStore: UsageStore(defaults: UserDefaults(suiteName: defaultsSuiteName)!),
            openInBrowser: { [effects] in effects.openedUrls.append($0) }
        )
        model.dismissPanel = { [effects] in effects.numDismissals += 1 }
        model.returnKeyboardFocusToPanel = { [effects] in effects.numKeyboardFocusRequests += 1 }
    }

    var numKeyboardFocusRequests: Int {
        effects.numKeyboardFocusRequests
    }

    var openedUrls: [URL] {
        effects.openedUrls
    }

    var numDismissals: Int {
        effects.numDismissals
    }

    var copiedText: String? {
        pasteboard.string(forType: .string)
    }

    var matchingItemNames: [String] {
        model.matchingItems.map(\.name)
    }

    func cleanUp() {
        pasteboard.releaseGlobally()
        UserDefaults.standard.removePersistentDomain(forName: defaultsSuiteName)
    }
}

@MainActor
final class QuickAccessModelTests: XCTestCase {
    private let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    private func makeHarness(
        ciphers: [[String: Any]] = [
            StateFileBuilder.makeLogin(id: "github", name: "GitHub", username: "octocat"),
            StateFileBuilder.makeLogin(id: "bank", name: "Bank", username: "alice"),
        ],
        settings: [String: Any] = [:]
    ) throws -> Harness {
        let harness = try Harness(ciphers: ciphers, settings: settings)
        addTeardownBlock { @MainActor in
            harness.cleanUp()
        }
        return harness
    }

    private func makeUnlockedHarness(
        ciphers: [[String: Any]]? = nil,
        settings: [String: Any] = [:]
    ) async throws -> Harness {
        let harness =
            try ciphers.map { try makeHarness(ciphers: $0, settings: settings) }
            ?? makeHarness(settings: settings)
        harness.model.prepareForShowing(frontmostAppName: nil)
        await harness.model.unlock()
        return harness
    }

    // MARK: - Unlocking

    func test_unlock__listsVaultItemsAsSuggestions() async throws {
        let harness = try await makeUnlockedHarness()

        XCTAssertTrue(harness.session.isUnlocked)
        XCTAssertEqual(harness.matchingItemNames, ["Bank", "GitHub"])
    }

    func test_unlock__explainsWhenTouchIdIsCancelled() async throws {
        let harness = try makeHarness()
        harness.desktop.unlockOutcome = .denied

        await harness.model.unlock()

        guard case .locked(let explanation) = harness.session.state else {
            return XCTFail("expected the session to stay locked")
        }
        XCTAssertEqual(explanation, "Touch ID was cancelled.")
        XCTAssertEqual(harness.matchingItemNames, [])
    }

    func test_unlock__explainsWhenDesktopAppNeedsTheMasterPasswordFirst() async throws {
        let harness = try makeHarness()
        harness.desktop.unlockOutcome = .unavailable(.unlockNeeded)

        await harness.model.unlock()

        guard case .locked(let explanation) = harness.session.state else {
            return XCTFail("expected the session to stay locked")
        }
        XCTAssertEqual(explanation?.contains("master password"), true)
    }

    func test_activateSelection__asksForUnlockWhileLocked() async throws {
        let harness = try makeHarness()
        harness.model.prepareForShowing(frontmostAppName: nil)

        harness.model.activateSelection()
        // The unlock runs in a task of its own; give it time to finish.
        for _ in 0..<200 where !harness.session.isUnlocked {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertTrue(harness.session.isUnlocked)
        XCTAssertEqual(harness.desktop.numUnlockRequests, 1)
        XCTAssertNil(harness.copiedText)
    }

    // MARK: - Copying

    func test_activateSelection__copiesPasswordOfSelectedItemAndClosesThePanel() async throws {
        let harness = try await makeUnlockedHarness()

        harness.model.moveSelection(by: 1)
        harness.model.activateSelection()

        XCTAssertEqual(harness.model.selectedItem?.name, "GitHub")
        XCTAssertEqual(harness.copiedText, "correct horse")
        XCTAssertEqual(harness.numDismissals, 1)
    }

    func test_copyPrimaryField__copiesUsername() async throws {
        let harness = try await makeUnlockedHarness()

        harness.model.copyPrimaryField()

        XCTAssertEqual(harness.copiedText, "alice")
        XCTAssertEqual(harness.numDismissals, 1)
    }

    func test_copyOneTimeCode__copiesTheCodeValidRightNow() async throws {
        let harness = try await makeUnlockedHarness()
        let configuration = try TotpConfiguration(authenticatorKey: StateFileBuilder.authenticatorKey)
        let codeBefore = TotpGenerator.generateCode(configuration: configuration, at: Date())

        harness.model.copyOneTimeCode()

        // The period may roll over between the two calls, so either code is right.
        let codeAfter = TotpGenerator.generateCode(configuration: configuration, at: Date())
        XCTAssertTrue(
            [codeBefore, codeAfter].contains(harness.copiedText), "copied \(harness.copiedText ?? "nothing")")
        XCTAssertEqual(harness.copiedText?.count, 6)
    }

    func test_copy__marksSecretsButNotUsernamesAsConcealed() async throws {
        let harness = try await makeUnlockedHarness()

        harness.model.copyPassword()
        let typesAfterPassword = harness.pasteboard.types ?? []
        harness.model.copyPrimaryField()
        let typesAfterUsername = harness.pasteboard.types ?? []

        XCTAssertTrue(typesAfterPassword.contains(concealedType))
        XCTAssertFalse(typesAfterUsername.contains(concealedType))
    }

    func test_activateSelection__refusesSecretOfItemWithMasterPasswordReprompt() async throws {
        let harness = try await makeUnlockedHarness(ciphers: [
            StateFileBuilder.makeLogin(name: "Protected", extra: ["reprompt": 1])
        ])

        harness.model.activateSelection()

        XCTAssertNil(harness.copiedText)
        XCTAssertEqual(harness.model.notice?.contains("master password"), true)
        XCTAssertEqual(harness.numDismissals, 0)

        harness.model.copyPrimaryField()

        XCTAssertEqual(harness.copiedText, "alice@example.com")
    }

    func test_copyOneTimeCode__explainsWhenItemHasNone() async throws {
        let loginWithoutCode = StateFileBuilder.makeLogin(
            name: "Plain",
            extra: [
                "login": ["username": Fixtures.encrypt("alice", with: Fixtures.userKey)]
            ])
        let harness = try await makeUnlockedHarness(ciphers: [loginWithoutCode])

        harness.model.copyOneTimeCode()

        XCTAssertNil(harness.copiedText)
        XCTAssertNotNil(harness.model.notice)
        XCTAssertEqual(harness.numDismissals, 0)
    }

    func test_activateSelection__suggestsUsedItemFirstNextTime() async throws {
        let harness = try await makeUnlockedHarness()

        harness.model.moveSelection(by: 1)
        harness.model.activateSelection()
        harness.model.prepareForShowing(frontmostAppName: nil)

        XCTAssertEqual(harness.matchingItemNames, ["GitHub", "Bank"])
    }

    // MARK: - Searching and navigating

    func test_updateQuery__narrowsTheListAndSelectsItsFirstItem() async throws {
        let harness = try await makeUnlockedHarness()
        harness.model.moveSelection(by: 1)

        harness.model.updateQuery("git")

        XCTAssertEqual(harness.matchingItemNames, ["GitHub"])
        XCTAssertEqual(harness.model.selectedItem?.name, "GitHub")
    }

    func test_updateQuery__keepsTheSelectionWhenTheTextDidNotChange() async throws {
        let harness = try await makeUnlockedHarness()
        harness.model.moveSelection(by: 1)

        // The search field reports its text again whenever it takes the keyboard focus.
        harness.model.updateQuery("")

        XCTAssertEqual(harness.model.selectedItem?.name, "GitHub")
    }

    func test_updateQuery__keepsTheNoticeWhenTheTextDidNotChange() async throws {
        let harness = try await makeUnlockedHarness(ciphers: [
            StateFileBuilder.makeLogin(name: "Protected", extra: ["reprompt": 1])
        ])
        harness.model.activateSelection()

        harness.model.updateQuery("")

        XCTAssertNotNil(harness.model.notice)
    }

    func test_prepareForShowing__suggestsItemNamedAfterTheAppInFront() async throws {
        let harness = try await makeUnlockedHarness()

        harness.model.prepareForShowing(frontmostAppName: "GitHub Desktop")
        XCTAssertEqual(harness.matchingItemNames, ["Bank", "GitHub"])

        harness.model.prepareForShowing(frontmostAppName: "GitHub")
        XCTAssertEqual(harness.matchingItemNames, ["GitHub", "Bank"])
    }

    func test_moveSelection__stopsAtBothEndsOfTheList() async throws {
        let harness = try await makeUnlockedHarness()

        harness.model.moveSelection(by: -1)
        XCTAssertEqual(harness.model.selectedItem?.name, "Bank")

        harness.model.moveSelection(by: 5)
        XCTAssertEqual(harness.model.selectedItem?.name, "GitHub")
    }

    func test_showActionsOfSelectedItem__listsWhatCanBeDoneWithTheItem() async throws {
        let harness = try await makeUnlockedHarness()

        harness.model.showActionsOfSelectedItem()

        XCTAssertEqual(
            harness.model.actions.map(\.title),
            ["Copy Username", "Copy Password", "Copy One-time code", "Open Website", "Copy Website"]
        )
        XCTAssertEqual(harness.model.actions.map(\.shortcutHint), ["⌘C", "⇧⌘C", "⌥⌘C", "⌥↩", nil])
    }

    func test_activateSelection__runsTheSelectedAction() async throws {
        let harness = try await makeUnlockedHarness()
        harness.model.showActionsOfSelectedItem()

        harness.model.moveSelection(by: 3)
        harness.model.activateSelection()

        XCTAssertEqual(harness.openedUrls, [URL(string: "https://example.com/login")!])
        XCTAssertNil(harness.copiedText)
        XCTAssertEqual(harness.numDismissals, 1)
    }

    func test_openWebsite__refusesAddressesThatAreNotWebPages() async throws {
        let loginWithAppAddress = StateFileBuilder.makeLogin(
            name: "App",
            extra: [
                "login": ["uris": [["uri": Fixtures.encrypt("ssh://example.com", with: Fixtures.userKey)]]]
            ])
        let harness = try await makeUnlockedHarness(ciphers: [loginWithAppAddress])

        harness.model.openWebsite()

        XCTAssertEqual(harness.openedUrls, [])
        XCTAssertNotNil(harness.model.notice)
        XCTAssertEqual(harness.numDismissals, 0)
    }

    func test_stepBack__leavesActionsThenClearsTheQueryThenClosesThePanel() async throws {
        let harness = try await makeUnlockedHarness()
        harness.model.updateQuery("git")
        harness.model.showActionsOfSelectedItem()

        harness.model.stepBack()
        XCTAssertEqual(harness.model.mode, .items)
        XCTAssertEqual(harness.model.query, "git")

        harness.model.stepBack()
        XCTAssertEqual(harness.model.query, "")
        XCTAssertEqual(harness.numDismissals, 0)

        harness.model.stepBack()
        XCTAssertEqual(harness.numDismissals, 1)
    }

    // MARK: - Website icons

    private func makeIconSettings(showsIcons: Bool = true) -> [String: Any] {
        [
            StateFileBuilder.settingKey("environment_environment"): [
                "region": "Self-hosted", "urls": ["base": "https://vault.example.com"],
            ],
            "global_domainSettings_showFavicons": showsIcons,
        ]
    }

    func test_websiteIconUrl__namesTheIconOnTheDesktopAppsIconService() async throws {
        let harness = try await makeUnlockedHarness(settings: makeIconSettings())
        let item = try XCTUnwrap(harness.model.selectedItem)

        XCTAssertEqual(
            harness.model.websiteIconUrl(of: item)?.absoluteString,
            "https://vault.example.com/icons/example.com/icon.png"
        )
    }

    func test_websiteIconUrl__givesNoIconWhenTheDesktopAppHidesWebsiteIcons() async throws {
        let harness = try await makeUnlockedHarness(settings: makeIconSettings(showsIcons: false))
        let item = try XCTUnwrap(harness.model.selectedItem)

        XCTAssertNil(harness.model.websiteIconUrl(of: item))
    }

    func test_loadIcon__fetchesEachIconOnceAndKeepsIt() async throws {
        let harness = try await makeUnlockedHarness(settings: makeIconSettings())
        let iconUrl = try XCTUnwrap(harness.model.websiteIconUrl(of: XCTUnwrap(harness.model.selectedItem)))

        XCTAssertNil(harness.model.iconStore.icon(at: iconUrl))
        await harness.model.iconStore.loadIcon(at: iconUrl)
        await harness.model.iconStore.loadIcon(at: iconUrl)

        XCTAssertNotNil(harness.model.iconStore.icon(at: iconUrl))
        XCTAssertEqual(harness.iconService.requestedUrls, [iconUrl])
    }

    func test_loadIcon__stillLoadsWhenTheRowThatAskedForItGoesAway() async throws {
        let harness = try await makeUnlockedHarness(settings: makeIconSettings())
        let iconUrl = try XCTUnwrap(harness.model.websiteIconUrl(of: XCTUnwrap(harness.model.selectedItem)))

        // A row that scrolls away or is filtered out cancels the task it asked for its icon in.
        let rowTask = Task { await harness.model.iconStore.loadIcon(at: iconUrl) }
        rowTask.cancel()
        await rowTask.value
        for _ in 0..<200 where harness.model.iconStore.icon(at: iconUrl) == nil {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertNotNil(harness.model.iconStore.icon(at: iconUrl))
    }

    func test_loadIcon__triesARequestThatFailedOnceMoreAndThenGivesUp() async throws {
        let harness = try await makeUnlockedHarness(settings: makeIconSettings())
        let iconUrl = try XCTUnwrap(harness.model.websiteIconUrl(of: XCTUnwrap(harness.model.selectedItem)))
        harness.iconService.setResponseData(nil)

        for _ in 0..<4 {
            await harness.model.iconStore.loadIcon(at: iconUrl)
        }

        XCTAssertNil(harness.model.iconStore.icon(at: iconUrl))
        XCTAssertEqual(harness.iconService.requestedUrls.count, 2)
    }

    func test_loadIcon__ignoresAnAnswerThatIsNotAnImage() async throws {
        let harness = try await makeUnlockedHarness(settings: makeIconSettings())
        let iconUrl = try XCTUnwrap(harness.model.websiteIconUrl(of: XCTUnwrap(harness.model.selectedItem)))
        harness.iconService.setResponseData(Data("<html>not found</html>".utf8))

        await harness.model.iconStore.loadIcon(at: iconUrl)
        await harness.model.iconStore.loadIcon(at: iconUrl)

        XCTAssertNil(harness.model.iconStore.icon(at: iconUrl))
        // An answer that is no icon is final; asking again would get the same.
        XCTAssertEqual(harness.iconService.requestedUrls.count, 1)
    }

    func test_lock__forgetsTheWebsiteIcons() async throws {
        let harness = try await makeUnlockedHarness(settings: makeIconSettings())
        let iconUrl = try XCTUnwrap(harness.model.websiteIconUrl(of: XCTUnwrap(harness.model.selectedItem)))
        await harness.model.iconStore.loadIcon(at: iconUrl)

        harness.session.lock()

        XCTAssertNil(harness.model.iconStore.icon(at: iconUrl))
    }

    // MARK: - Locking and following the desktop app

    func test_lock__makesTheOpenPanelForgetTheVault() async throws {
        let harness = try await makeUnlockedHarness()
        harness.model.showActionsOfSelectedItem()

        harness.session.lock()
        harness.model.copyPassword()
        harness.model.copyPrimaryField()
        harness.model.copyOneTimeCode()
        harness.model.openWebsite()

        XCTAssertNil(harness.copiedText)
        XCTAssertEqual(harness.openedUrls, [])
        XCTAssertEqual(harness.matchingItemNames, [])
        XCTAssertEqual(harness.model.mode, .items)
        XCTAssertEqual(harness.numDismissals, 0)
    }

    func test_prepareForShowing__locksWhenTheVaultTimeoutPassedSinceLastUse() async throws {
        let harness = try await makeUnlockedHarness(settings: [
            StateFileBuilder.settingKey("vaultTimeoutSettings_vaultTimeout"): 1
        ])

        harness.clock.advance(bySeconds: 61)
        harness.model.prepareForShowing(frontmostAppName: nil)

        XCTAssertFalse(harness.session.isUnlocked)
        XCTAssertEqual(harness.matchingItemNames, [])
    }

    func test_copyPassword__locksInsteadOfCopyingWhenTheVaultTimeoutPassed() async throws {
        let harness = try await makeUnlockedHarness(settings: [
            StateFileBuilder.settingKey("vaultTimeoutSettings_vaultTimeout"): 1
        ])

        harness.clock.advance(bySeconds: 61)
        harness.model.copyPassword()

        XCTAssertNil(harness.copiedText)
        XCTAssertFalse(harness.session.isUnlocked)
    }

    func test_copyPassword__locksWhenTheSystemHasBeenIdleLongerThanTheDesktopAppAllows() async throws {
        let harness = try await makeUnlockedHarness(settings: [
            StateFileBuilder.settingKey("vaultTimeoutSettings_vaultTimeout"): "onIdle"
        ])

        // The periodic check is late; a use of the vault has to apply the timeout by itself.
        harness.clock.systemIdleSeconds = 600
        harness.model.copyPassword()

        XCTAssertNil(harness.copiedText)
        XCTAssertFalse(harness.session.isUnlocked)
    }

    func test_systemDidWake__locksWhenIdleTimeAndSleepTogetherExceedWhatTheDesktopAppAllows() async throws {
        let harness = try await makeUnlockedHarness(settings: [
            StateFileBuilder.settingKey("vaultTimeoutSettings_vaultTimeout"): "onIdle"
        ])

        // The lid closes after a minute without input and opens an hour later. No periodic check
        // ran in between, and the key press that wakes the Mac resets the system's idle time.
        harness.clock.systemIdleSeconds = 60
        harness.session.systemWillSleep()
        harness.clock.advance(bySeconds: 3600)
        harness.clock.systemIdleSeconds = 0
        harness.session.systemDidWake()
        harness.model.copyPassword()

        XCTAssertNil(harness.copiedText)
        XCTAssertFalse(harness.session.isUnlocked)
    }

    func test_systemDidWake__keepsTheVaultUnlockedAfterAShortSleep() async throws {
        let harness = try await makeUnlockedHarness(settings: [
            StateFileBuilder.settingKey("vaultTimeoutSettings_vaultTimeout"): "onIdle"
        ])

        harness.clock.systemIdleSeconds = 60
        harness.session.systemWillSleep()
        harness.clock.advance(bySeconds: 120)
        harness.clock.systemIdleSeconds = 0
        harness.session.systemDidWake()

        XCTAssertTrue(harness.session.isUnlocked)
    }

    func test_updateQuery__countsAsUseForTheVaultTimeout() async throws {
        let harness = try await makeUnlockedHarness(settings: [
            StateFileBuilder.settingKey("vaultTimeoutSettings_vaultTimeout"): 1
        ])

        harness.clock.advance(bySeconds: 40)
        harness.model.updateQuery("git")
        harness.clock.advance(bySeconds: 40)
        harness.model.copyPassword()

        XCTAssertEqual(harness.copiedText, "correct horse")
    }

    func test_unlock__returnsTheKeyboardFocusToThePanelAlsoWhenStartedWithReturn() async throws {
        let harness = try makeHarness()
        harness.model.prepareForShowing(frontmostAppName: nil)

        harness.model.activateSelection()
        for _ in 0..<200 where !harness.session.isUnlocked {
            try await Task.sleep(for: .milliseconds(10))
        }
        // The Touch ID prompt takes the keyboard; without this the panel stays deaf.
        for _ in 0..<200 where harness.numKeyboardFocusRequests == 0 {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertEqual(harness.numKeyboardFocusRequests, 1)
    }

    func test_prepareForShowing__picksUpAWriteThatHappenedWhileUnlocking() async throws {
        let harness = try makeHarness()
        let stateFileAfterSync = try StateFileBuilder.makeStateFile(ciphers: [
            StateFileBuilder.makeLogin(id: "new", name: "Synced meanwhile")
        ])
        harness.desktop.afterLoadState = { [desktop = harness.desktop] in
            desktop.afterLoadState = {}
            desktop.stateFile = stateFileAfterSync
            desktop.stateModificationDate = Date(timeIntervalSince1970: 2_000)
        }

        await harness.model.unlock()
        XCTAssertEqual(harness.matchingItemNames, ["Bank", "GitHub"])

        harness.model.prepareForShowing(frontmostAppName: nil)
        XCTAssertEqual(harness.matchingItemNames, ["Synced meanwhile"])
    }

    func test_handle__locksOnTheEventTheDesktopAppsVaultTimeoutNames() async throws {
        let harness = try await makeUnlockedHarness(settings: [
            StateFileBuilder.settingKey("vaultTimeoutSettings_vaultTimeout"): "onSleep"
        ])

        harness.session.handle(.screenLocked)
        XCTAssertTrue(harness.session.isUnlocked)

        harness.session.handle(.systemWillSleep)
        XCTAssertFalse(harness.session.isUnlocked)

        harness.model.prepareForShowing(frontmostAppName: nil)
        XCTAssertEqual(harness.matchingItemNames, [])
    }

    func test_lock__requiresTouchIdAgain() async throws {
        let harness = try await makeUnlockedHarness()

        harness.session.lock()
        harness.model.prepareForShowing(frontmostAppName: nil)
        XCTAssertEqual(harness.matchingItemNames, [])

        await harness.model.unlock()
        XCTAssertEqual(harness.desktop.numUnlockRequests, 2)
        XCTAssertEqual(harness.matchingItemNames, ["Bank", "GitHub"])
    }

    func test_prepareForShowing__picksUpItemsTheDesktopAppSyncedSinceUnlock() async throws {
        let harness = try await makeUnlockedHarness()

        harness.desktop.stateFile = try StateFileBuilder.makeStateFile(ciphers: [
            StateFileBuilder.makeLogin(id: "new", name: "New login")
        ])
        harness.desktop.stateModificationDate = Date(timeIntervalSince1970: 2_000)
        harness.model.prepareForShowing(frontmostAppName: nil)

        XCTAssertEqual(harness.matchingItemNames, ["New login"])
        XCTAssertEqual(harness.desktop.numUnlockRequests, 1)
    }

    func test_prepareForShowing__locksWhenTheDesktopAppSwitchedToAnotherAccount() async throws {
        let harness = try await makeUnlockedHarness()

        harness.desktop.stateFile = try StateFileBuilder.makeStateFile(
            ciphers: [],
            userId: "99999999-0000-0000-0000-000000000000"
        )
        harness.desktop.stateModificationDate = Date(timeIntervalSince1970: 2_000)
        harness.model.prepareForShowing(frontmostAppName: nil)

        XCTAssertFalse(harness.session.isUnlocked)
        XCTAssertEqual(harness.matchingItemNames, [])
    }

    func test_unlock__adoptsTheDesktopAppsClipboardClearDelay() async throws {
        let harness = try await makeUnlockedHarness(settings: [
            StateFileBuilder.settingKey("autofillSettingsLocal_clearClipboardDelay"): "tenSeconds"
        ])

        XCTAssertEqual(harness.session.settings.clipboardClearDelay, .seconds(10))
    }
}

@MainActor
final class ClipboardWriterTests: XCTestCase {
    func test_copy__removesTheValueAfterTheDelay() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let clipboard = ClipboardWriter(pasteboard: pasteboard)

        clipboard.copy("secret", isConcealed: true, clearDelay: .seconds(1))
        XCTAssertEqual(pasteboard.string(forType: .string), "secret")

        try await Task.sleep(for: .milliseconds(1_500))
        XCTAssertNil(pasteboard.string(forType: .string))
    }

    func test_copy__leavesTheClipboardAloneWhenSomethingElseWasCopiedSince() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let clipboard = ClipboardWriter(pasteboard: pasteboard)

        clipboard.copy("secret", isConcealed: true, clearDelay: .seconds(1))
        pasteboard.clearContents()
        pasteboard.setString("copied by the user", forType: .string)

        try await Task.sleep(for: .milliseconds(1_500))
        XCTAssertEqual(pasteboard.string(forType: .string), "copied by the user")
    }

    func test_clearIfOwnCopyIsStillThere__removesValueThatHasNoClearDelay() async throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let clipboard = ClipboardWriter(pasteboard: pasteboard)

        clipboard.copy("kept until quit", isConcealed: false, clearDelay: .never)
        XCTAssertEqual(pasteboard.string(forType: .string), "kept until quit")

        // What quitting the app does, so that nothing copied outlives it.
        clipboard.clearIfOwnCopyIsStillThere()
        XCTAssertNil(pasteboard.string(forType: .string))
    }
}
