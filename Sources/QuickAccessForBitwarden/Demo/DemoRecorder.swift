import AppKit
import ImageIO
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// Records the screencast shown in the README: plays a scripted session against the demo vault,
/// draws the panel offscreen and writes one animated GIF per appearance. Nothing of the screen is
/// captured, so no desktop, window or real vault can end up in the recording.
@MainActor
enum DemoRecorder {
    enum RecordingError: Error {
        case frameCouldNotBeDrawn
        case fileCouldNotBeWritten(URL)
    }

    /// One moment of the screencast: what happens, what the caption says, how long it stays.
    private struct Step {
        let caption: String
        let seconds: Double
        let perform: @MainActor (QuickAccessModel, Stage) async -> Void
    }

    /// What the frame shows around the panel.
    @MainActor
    @Observable
    final class Stage {
        var caption = ""
        var isPanelVisible = false
    }

    private static let margin: CGFloat = 28
    private static let captionHeight: CGFloat = 44
    /// Long enough for the view to redraw and for the icons of new rows to arrive.
    private static let settleTime = Duration.milliseconds(350)
    private static let demoDefaultsSuiteName = "dev.filo.quick-access-for-bitwarden.screencast"

    private static let steps = [
        Step(caption: "⇧⌘Space opens the panel from any app", seconds: 1.6) { _, _ in },
        Step(caption: "The items used most come first", seconds: 1.8) { model, stage in
            model.prepareForShowing(frontmostAppName: nil)
            await model.unlock()
            stage.isPanelVisible = true
        },
        Step(caption: "Type to search", seconds: 0.4) { model, _ in model.updateQuery("p") },
        Step(caption: "Type to search", seconds: 0.4) { model, _ in model.updateQuery("pi") },
        Step(caption: "Type to search", seconds: 1.2) { model, _ in model.updateQuery("pix") },
        Step(caption: "↑ ↓ select an item", seconds: 1.2) { model, _ in model.moveSelection(by: 1) },
        Step(caption: "→ shows everything the item offers", seconds: 1.6) { model, _ in
            model.showActionsOfSelectedItem()
        },
        Step(caption: "↑ ↓ pick what to copy", seconds: 0.6) { model, _ in model.moveSelection(by: 1) },
        Step(caption: "↑ ↓ pick what to copy", seconds: 1.2) { model, _ in model.moveSelection(by: 1) },
        Step(caption: "↩ copies it and closes the panel", seconds: 2.2) { model, _ in model.activateSelection() },
    ]

    /// Writes `<outputPathPrefix>-dark.gif` and `<outputPathPrefix>-light.gif`.
    static func record(outputPathPrefix: String) async throws {
        let appearances: [(name: NSAppearance.Name, fileSuffix: String)] = [(.darkAqua, "dark"), (.aqua, "light")]
        for appearance in appearances {
            let frames = try await playScript(appearanceName: appearance.name)
            let gifFile = URL(fileURLWithPath: "\(outputPathPrefix)-\(appearance.fileSuffix).gif")
            try writeGif(frames, to: gifFile)
            print("wrote \(gifFile.path) (\(frames.count) frames)")
        }
    }

    private static func playScript(appearanceName: NSAppearance.Name) async throws -> [(
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
        let model = QuickAccessModel(
            session: VaultSession(desktop: try DemoDesktop()),
            iconStore: WebsiteIconStore(fetchIconData: DemoIcons.makeIconData),
            clipboard: ClipboardWriter(pasteboard: pasteboard),
            usageStore: UsageStore(defaults: UserDefaults(suiteName: demoDefaultsSuiteName) ?? .standard),
            openInBrowser: { _ in },
            // The screencast is in English whatever the language of the Mac that records it.
            preferredSystemLanguages: ["en"]
        )
        model.dismissPanel = { stage.isPanelVisible = false }

        let frameSize = CGSize(
            width: QuickAccessView.defaultPanelSize.width + 2 * margin,
            height: QuickAccessView.defaultPanelSize.height + captionHeight + 2 * margin
        )
        let hostingView = NSHostingView(rootView: FrameView(model: model, stage: stage))
        hostingView.frame = NSRect(origin: .zero, size: frameSize)
        // The view only draws completely inside a window; this one never comes on screen.
        let offscreenWindow = NSWindow(
            contentRect: hostingView.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        offscreenWindow.appearance = NSAppearance(named: appearanceName)
        offscreenWindow.contentView = hostingView

        var frames = [(image: CGImage, seconds: Double)]()
        for step in steps {
            stage.caption = step.caption
            await step.perform(model, stage)
            try await Task.sleep(for: settleTime)
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
        let model: QuickAccessModel
        let stage: Stage

        var body: some View {
            VStack(spacing: 0) {
                QuickAccessView(model: model)
                    .frame(
                        width: QuickAccessView.defaultPanelSize.width,
                        height: QuickAccessView.defaultPanelSize.height
                    )
                    .background(Color(nsColor: .windowBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: QuickAccessView.cornerRadius, style: .continuous))
                    .opacity(stage.isPanelVisible ? 1 : 0)
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
