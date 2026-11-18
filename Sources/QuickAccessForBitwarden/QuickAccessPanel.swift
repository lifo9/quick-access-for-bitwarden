import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A borderless floating panel that takes keyboard input without activating this app, so the app
/// the user was working in stays in front and gets the focus back when the panel closes. It can
/// be resized by its edges, down to a minimum size.
private final class FloatingPanel: NSPanel {
    init(contentSize: CGSize, minimumSize: CGSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        animationBehavior = .utilityWindow
        minSize = minimumSize
    }

    // Borderless windows refuse the keyboard focus unless told otherwise.
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}

/// Shows and hides the quick access panel and turns key presses into commands of the model.
@MainActor
final class QuickAccessPanelController: NSObject, NSWindowDelegate {
    private let model: QuickAccessModel
    /// The name under which the system remembers where the panel was put and how large.
    private static let frameAutosaveName = "QuickAccessPanel"

    private let panel = FloatingPanel(
        contentSize: QuickAccessView.defaultPanelSize,
        minimumSize: QuickAccessView.minimumPanelSize
    )
    private var keyDownMonitor: Any?

    init(model: QuickAccessModel) {
        self.model = model
        super.init()

        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = QuickAccessView.cornerRadius
        background.layer?.cornerCurve = .continuous
        background.layer?.masksToBounds = true

        let hostingView = NSHostingView(rootView: QuickAccessView(model: model))
        // The panel's size is the user's to choose; the content adapts to it, not the reverse.
        hostingView.sizingOptions = []
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: background.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])

        panel.contentView = background
        panel.delegate = self
        // A panel that was moved or resized comes back where and how it was left; until then it
        // gets the default place.
        if !panel.setFrameUsingName(Self.frameAutosaveName) {
            placeAtDefaultPosition()
        }
        panel.setFrameAutosaveName(Self.frameAutosaveName)
        model.dismissPanel = { [weak self] in
            self?.hide()
        }
        model.returnKeyboardFocusToPanel = { [weak self] in
            guard let self, self.panel.isVisible else {
                return
            }
            self.panel.makeKeyAndOrderFront(nil)
        }
        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] keyDownEvent in
            guard let self, keyDownEvent.window === self.panel else {
                return keyDownEvent
            }
            // Returning nil consumes the event, so that the search field does not handle it too.
            return self.handle(keyDownEvent) ? nil : keyDownEvent
        }
    }

    func toggle() {
        if panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        // Read before the panel opens: this is the app the user summoned the panel from.
        model.prepareForShowing(frontmostAppName: NSWorkspace.shared.frontmostApplication?.localizedName)
        panel.makeKeyAndOrderFront(nil)

        if !model.session.isUnlocked {
            Task {
                await model.unlock()
            }
        }
    }

    func hide() {
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        // Clicking elsewhere closes the panel. While unlocking, the Touch ID prompt is what took
        // the focus, and the panel has to stay to show the result.
        if case .unlocking = model.session.state {
            return
        }
        hide()
    }

    private func placeAtDefaultPosition() {
        guard let visibleFrame = NSScreen.main?.visibleFrame else {
            return
        }
        // Upper third of the screen, where Spotlight-style panels sit.
        let panelOrigin = NSPoint(
            x: visibleFrame.midX - panel.frame.width / 2,
            y: visibleFrame.minY + visibleFrame.height * 0.72 - panel.frame.height
        )
        panel.setFrameOrigin(panelOrigin)
    }

    /// Inside the query the right arrow moves the caret, as the left arrow does; only at its
    /// end is it free to open the actions of the selected item.
    private var isCaretAtEndOfQuery: Bool {
        guard let queryEditor = panel.firstResponder as? NSTextView else {
            return true
        }
        let selection = queryEditor.selectedRange()
        return selection.length == 0 && selection.location == (queryEditor.string as NSString).length
    }

    /// - Returns: Whether the key press was a command of the panel.
    private func handle(_ keyDownEvent: NSEvent) -> Bool {
        let modifiers = keyDownEvent.modifierFlags.intersection([.command, .option, .shift, .control])
        let isLetterC = keyDownEvent.charactersIgnoringModifiers?.lowercased() == "c"

        switch (Int(keyDownEvent.keyCode), modifiers) {
        case (kVK_DownArrow, []):
            model.moveSelection(by: 1)
        case (kVK_UpArrow, []):
            model.moveSelection(by: -1)
        case (kVK_Return, []), (kVK_ANSI_KeypadEnter, []):
            model.activateSelection()
        case (kVK_Return, [.option]):
            model.openWebsite()
        case (kVK_RightArrow, []) where isCaretAtEndOfQuery:
            model.showActionsOfSelectedItem()
        case (kVK_LeftArrow, []) where model.mode != .items:
            model.showItems()
        case (kVK_Escape, []):
            model.stepBack()
        case (_, [.command]) where isLetterC:
            model.copyPrimaryField()
        case (_, [.command, .shift]) where isLetterC:
            model.copyPassword()
        case (_, [.command, .option]) where isLetterC:
            model.copyOneTimeCode()
        default:
            // Typing belongs to the search field, which is hidden but still focused while the
            // actions of an item are shown; there, every other key press is swallowed.
            return model.mode != .items
        }
        return true
    }
}
