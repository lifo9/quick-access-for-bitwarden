import AppKit
import ImageIO
import Observation
import QuickAccessCore
import SwiftUI
import UniformTypeIdentifiers

/// Records the screencast shown in the README: plays a scripted session against the demo vault,
/// draws the panel offscreen and writes one animated GIF per appearance. Nothing of the screen is
/// captured, so no desktop, window or real vault can end up in the recording.
@MainActor
enum DemoRecorder {
    enum RecordingError: Error {
        case appIconNotFound(path: String)
        case vaultDidNotUnlock
        /// The demo was not in the state that the caption of this step describes.
        case stepMissedItsState(caption: String)
        case frameCouldNotBeDrawn
        case fileCouldNotBeWritten(URL)
    }

    /// Where `just screencast` finds the app's icon: relative to the repository's root, from
    /// which it runs the recorder.
    static let defaultAppIconPath = "Bundle/AppIcon.icns"

    /// One moment of the screencast: what happens, what the caption says, how long it stays.
    private struct Step {
        let caption: String
        let seconds: Double
        let isPanelOpen: Bool
        /// Whether the demo is where the caption says, asked when the frame is taken. A script
        /// that has drifted from the app then fails instead of recording something else.
        let isReached: @MainActor (DemoSetup) -> Bool
        let perform: @MainActor (DemoSetup) async throws -> Void

        init(
            caption: String,
            seconds: Double,
            isPanelOpen: Bool = true,
            isReached: @escaping @MainActor (DemoSetup) -> Bool,
            perform: @escaping @MainActor (DemoSetup) async throws -> Void
        ) {
            self.caption = caption
            self.seconds = seconds
            self.isPanelOpen = isPanelOpen
            self.isReached = isReached
            self.perform = perform
        }
    }

    /// What the steps act on.
    @MainActor
    private struct DemoSetup {
        let desktop: DemoDesktop
        let model: QuickAccessModel
        let stage: Stage
    }

    /// What the frame shows around the panel.
    @MainActor
    @Observable
    final class Stage {
        var caption = ""
        var isPanelVisible = false
        var panelSize = QuickAccessView.defaultPanelSize
    }

    private static let margin: CGFloat = 28
    private static let captionHeight: CGFloat = 44
    /// Long enough for the view to redraw and for the icons of new rows to arrive.
    private static let settleTime = Duration.milliseconds(350)
    /// Longer than the settle time, so that one frame shows the panel waiting for Touch ID.
    private static let touchIdDuration = settleTime * 3
    private static let unlockTimeout = Duration.seconds(5)
    private static let demoDefaultsSuiteName = "dev.filo.quick-access-for-bitwarden.screencast"
    /// A panel dragged smaller, to show that its footer makes do with less room.
    private static let resizedPanelSize = CGSize(width: 470, height: 300)
    /// The item of the demo vault that the script copies from, and so the one used most.
    private static let copiedItemName = "Pixel Forge (studio)"

    private static let unlockSteps = [
        Step(
            caption: "⇧⌘Space opens the panel from any app", seconds: 1.6, isPanelOpen: false,
            isReached: { _ in true },
            perform: { _ in }
        ),
        Step(
            caption: "Locked by Bitwarden's vault timeout, unlocked with its Touch ID", seconds: 2.0,
            isReached: { demo in isUnlocking(demo.model) },
            perform: { demo in
                // The frame is taken while the pretend Touch ID prompt is still up.
                openPanel(demo)
            }
        ),
        Step(
            caption: "The vault, with the icons of its websites", seconds: 2.0,
            isReached: { demo in !demo.model.matchingItems.isEmpty },
            perform: { demo in
                try await waitUntilUnlocked(demo.model)
            }
        ),
    ]

    private static let copySteps =
        makeTypingSteps(of: "pix") + [
            Step(
                caption: "↑ ↓ select an item", seconds: 1.2,
                isReached: { demo in demo.model.selectedItem?.name == copiedItemName },
                perform: { demo in
                    demo.model.moveSelection(by: 1)
                }
            ),
            Step(
                caption: "→ shows everything the item offers", seconds: 1.6,
                isReached: { demo in isShowingActions(demo.model, ofItemKind: .login) },
                perform: { demo in
                    demo.model.showActionsOfSelectedItem()
                }
            ),
            Step(
                caption: "↑ ↓ pick what to copy", seconds: 0.6,
                isReached: { demo in demo.model.selectedActionIndex == 1 },
                perform: { demo in
                    demo.model.moveSelection(by: 1)
                }
            ),
            Step(
                caption: "↑ ↓ pick what to copy", seconds: 1.2,
                isReached: { demo in demo.model.selectedActionIndex == 2 },
                perform: { demo in
                    demo.model.moveSelection(by: 1)
                }
            ),
            Step(
                caption: "↩ copies it and closes the panel", seconds: 2.0, isPanelOpen: false,
                isReached: { _ in true },
                perform: { demo in
                    demo.model.activateSelection()
                }
            ),
            Step(
                caption: "Next time, what you use most comes first", seconds: 2.0,
                isReached: { demo in demo.model.matchingItems.first?.name == copiedItemName },
                perform: { demo in
                    openPanel(demo)
                }
            ),
        ]

    private static let masterPasswordRepromptSteps =
        makeTypingSteps(of: "har") + [
            Step(
                caption: "An item with master password re-prompt keeps its secrets", seconds: 2.6,
                isReached: { demo in demo.model.notice == .masterPasswordRepromptRequired },
                perform: { demo in
                    demo.model.activateSelection()
                }
            )
        ]

    private static let cardSteps =
        [
            Step(
                caption: "esc clears the search", seconds: 0.8,
                isReached: { demo in demo.model.query.isEmpty },
                perform: { demo in
                    demo.model.stepBack()
                }
            )
        ]
        + makeTypingSteps(of: "card") + [
            Step(
                caption: "Cards, notes, identities and SSH keys work the same way", seconds: 2.2,
                isReached: { demo in isShowingActions(demo.model, ofItemKind: .card) },
                perform: { demo in
                    demo.model.showActionsOfSelectedItem()
                }
            )
        ]

    private static let windowSteps = [
        Step(
            caption: "Drag the panel to move it, its edges to resize it", seconds: 2.2,
            isReached: { demo in demo.model.mode == .items && !demo.model.matchingItems.isEmpty },
            perform: { demo in
                demo.model.showItems()
                demo.model.updateQuery("")
                demo.stage.panelSize = resizedPanelSize
            }
        )
    ]

    private static let languageSteps = [(desktopLocale: "sk", language: AppLanguage.slovak), ("cs", .czech)].map {
        desktopLocale, language in
        Step(
            caption: "Slovak and Czech, following Bitwarden's language or the system's", seconds: 2.4,
            isReached: { demo in
                isShowingActions(demo.model, ofItemKind: .login)
                    && demo.model.strings.searchPlaceholder == AppStrings.strings(for: language).searchPlaceholder
            },
            perform: { demo in
                demo.stage.panelSize = QuickAccessView.defaultPanelSize
                try demo.desktop.chooseLanguage(desktopLocale: desktopLocale)
                // Opening the panel is when the app picks up what the desktop app has changed.
                openPanel(demo)
                demo.model.showActionsOfSelectedItem()
            }
        )
    }

    private static let steps =
        unlockSteps + copySteps + masterPasswordRepromptSteps + cardSteps + windowSteps + languageSteps

    /// One step per key pressed; the last one stays for the list to be read.
    private static func makeTypingSteps(of typedText: String) -> [Step] {
        typedText.indices.map { lastCharacterIndex in
            let typedSoFar = String(typedText[...lastCharacterIndex])
            let isWholeText = typedSoFar == typedText
            return Step(
                caption: "Type to search", seconds: isWholeText ? 1.2 : 0.4,
                isReached: { demo in demo.model.query == typedSoFar && !demo.model.matchingItems.isEmpty },
                perform: { demo in
                    demo.model.updateQuery(typedSoFar)
                }
            )
        }
    }

    /// What the panel's controller does when the hot key is pressed: a locked vault is asked to
    /// unlock at once, without a key press of its own.
    private static func openPanel(_ demo: DemoSetup) {
        demo.model.prepareForShowing(frontmostAppName: nil)
        demo.stage.isPanelVisible = true
        if !demo.model.session.isUnlocked {
            Task { await demo.model.unlock() }
        }
    }

    private static func isUnlocking(_ model: QuickAccessModel) -> Bool {
        if case .unlocking = model.session.state { true } else { false }
    }

    private static func isShowingActions(_ model: QuickAccessModel, ofItemKind itemKind: VaultItemKind) -> Bool {
        if case .actions(let item) = model.mode { item.kind == itemKind } else { false }
    }

    /// The unlock that opening the panel starts runs on its own; this waits for it to end.
    private static func waitUntilUnlocked(_ model: QuickAccessModel) async throws {
        let deadline = ContinuousClock.now + unlockTimeout
        while !model.session.isUnlocked {
            guard ContinuousClock.now < deadline else {
                throw RecordingError.vaultDidNotUnlock
            }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    /// Writes `<outputPathPrefix>-dark.gif` and `<outputPathPrefix>-light.gif`.
    static func record(outputPathPrefix: String, appIconPath: String = defaultAppIconPath) async throws {
        guard let appIcon = NSImage(contentsOfFile: appIconPath) else {
            throw RecordingError.appIconNotFound(path: appIconPath)
        }
        let appearances: [(name: NSAppearance.Name, fileSuffix: String)] = [(.darkAqua, "dark"), (.aqua, "light")]
        for appearance in appearances {
            let frames = try await playScript(appearanceName: appearance.name, appIcon: appIcon)
            let gifFile = URL(fileURLWithPath: "\(outputPathPrefix)-\(appearance.fileSuffix).gif")
            try writeGif(frames, to: gifFile)
            print("wrote \(gifFile.path) (\(frames.count) frames)")
        }
    }

    private static func playScript(appearanceName: NSAppearance.Name, appIcon: NSImage) async throws -> [(
        image: CGImage, seconds: Double
    )] {
        // A private pasteboard and private preferences: recording must not touch the clipboard
        // or the use counts of the person running it.
        let pasteboard = NSPasteboard.withUniqueName()
        UserDefaults.standard.removePersistentDomain(forName: demoDefaultsSuiteName)
        defer {
            pasteboard.releaseGlobally()
            UserDefaults.standard.removePersistentDomain(forName: demoDefaultsSuiteName)
        }
        let stage = Stage()
        let desktop = try DemoDesktop(touchIdDuration: touchIdDuration)
        let model = QuickAccessModel(
            session: VaultSession(desktop: desktop),
            iconStore: WebsiteIconStore(fetchIconData: DemoIcons.makeIconData),
            clipboard: ClipboardWriter(pasteboard: pasteboard),
            usageStore: UsageStore(defaults: UserDefaults(suiteName: demoDefaultsSuiteName) ?? .standard),
            openInBrowser: { _ in },
            // The screencast starts in English whatever the language of the Mac that records it.
            preferredSystemLanguages: ["en"]
        )
        model.dismissPanel = { stage.isPanelVisible = false }
        let demo = DemoSetup(desktop: desktop, model: model, stage: stage)

        let frameSize = CGSize(
            width: QuickAccessView.defaultPanelSize.width + 2 * margin,
            height: QuickAccessView.defaultPanelSize.height + captionHeight + 2 * margin
        )
        let hostingView = NSHostingView(rootView: FrameView(model: model, stage: stage, appIcon: appIcon))
        hostingView.frame = NSRect(origin: .zero, size: frameSize)
        // The view only draws completely inside a window; this one never comes on screen.
        let offscreenWindow = NSWindow(
            contentRect: hostingView.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        offscreenWindow.appearance = NSAppearance(named: appearanceName)
        offscreenWindow.contentView = hostingView

        var frames = [(image: CGImage, seconds: Double)]()
        for step in steps {
            stage.caption = step.caption
            try await step.perform(demo)
            try await Task.sleep(for: settleTime)
            guard stage.isPanelVisible == step.isPanelOpen, step.isReached(demo) else {
                throw RecordingError.stepMissedItsState(caption: step.caption)
            }
            hostingView.layoutSubtreeIfNeeded()
            guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
                throw RecordingError.frameCouldNotBeDrawn
            }
            hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
            guard let frameImage = bitmap.cgImage else {
                throw RecordingError.frameCouldNotBeDrawn
            }
            frames.append((frameImage, step.seconds))
        }
        return frames
    }

    private static func writeGif(_ frames: [(image: CGImage, seconds: Double)], to gifFile: URL) throws {
        guard
            let destination = CGImageDestinationCreateWithURL(
                gifFile as CFURL, UTType.gif.identifier as CFString, frames.count, nil)
        else {
            throw RecordingError.fileCouldNotBeWritten(gifFile)
        }
        // A loop count of zero repeats the animation forever.
        let fileProperties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]]
        CGImageDestinationSetProperties(destination, fileProperties as CFDictionary)
        for frame in frames {
            let frameProperties = [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFDelayTime: frame.seconds,
                    kCGImagePropertyGIFUnclampedDelayTime: frame.seconds,
                ]
            ]
            CGImageDestinationAddImage(destination, frame.image, frameProperties as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else {
            throw RecordingError.fileCouldNotBeWritten(gifFile)
        }
    }

    /// The panel on a plain backdrop, with a caption below that says which keys were pressed.
    private struct FrameView: View {
        private static let appIconSize: CGFloat = 128

        let model: QuickAccessModel
        let stage: Stage
        let appIcon: NSImage

        var body: some View {
            VStack(spacing: 0) {
                ZStack {
                    // While the panel is closed the app's icon stands in its place.
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: Self.appIconSize, height: Self.appIconSize)
                        .opacity(stage.isPanelVisible ? 0 : 1)
                    QuickAccessView(model: model)
                        .frame(width: stage.panelSize.width, height: stage.panelSize.height)
                        .background(Color(nsColor: .windowBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: QuickAccessView.cornerRadius, style: .continuous))
                        .opacity(stage.isPanelVisible ? 1 : 0)
                }
                // The frame keeps its size whatever the panel's.
                .frame(
                    width: QuickAccessView.defaultPanelSize.width,
                    height: QuickAccessView.defaultPanelSize.height
                )
                Text(stage.caption)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(height: DemoRecorder.captionHeight, alignment: .bottom)
            }
            .padding(DemoRecorder.margin)
            // White in the light appearance and near black in the dark one, like the pages the
            // recording is shown on.
            .background(Color(nsColor: .textBackgroundColor))
        }
    }
}
