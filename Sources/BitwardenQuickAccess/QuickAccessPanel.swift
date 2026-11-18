import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A borderless floating panel that takes keyboard input without activating this app, so the app
/// the user was working in stays in front and gets the focus back when the panel closes.
private final class FloatingPanel: NSPanel {
    init(contentSize: CGSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .nonactivatingPanel],
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
    private static let cornerRadius: CGFloat = 14

    private let model: QuickAccessModel
    private let panel = FloatingPanel(contentSize: QuickAccessView.panelSize)
    private var keyDownMonitor: Any?

    init(model: QuickAccessModel) {
        self.model = model
        super.init()

        let background = NSVisualEffectView()
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = Self.cornerRadius
        background.layer?.masksToBounds = true

        let hostingView = NSHostingView(rootView: QuickAccessView(model: model))
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
        model.dismissPanel = { [weak self] in
            self?.hide()
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
        positionOnScreenWithMouse()
        panel.makeKeyAndOrderFront(nil)

        if !model.session.isUnlocked {
            Task {
                await model.unlock()
                // The Touch ID prompt took the keyboard focus; take it back.
                if panel.isVisible {
                    panel.makeKeyAndOrderFront(nil)
                }
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

    private func positionOnScreenWithMouse() {
        let mouseLocation = NSEvent.mouseLocation
        let screenWithMouse = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
        guard let visibleFrame = screenWithMouse?.visibleFrame else {
            return
        }
        // Upper third of the screen, where Spotlight-style panels sit.
        let panelOrigin = NSPoint(
            x: visibleFrame.midX - QuickAccessView.panelSize.width / 2,
            y: visibleFrame.minY + visibleFrame.height * 0.72 - QuickAccessView.panelSize.height
        )
        panel.setFrameOrigin(panelOrigin)
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
        case (kVK_RightArrow, []):
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
