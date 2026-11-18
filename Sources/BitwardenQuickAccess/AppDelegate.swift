import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let session = VaultSession(desktop: InstalledDesktopApp())
    private let clipboard = ClipboardWriter()
    private var panelController: QuickAccessPanelController?
    private var hotKey: GlobalHotKey?
    private var statusItem: NSStatusItem?
    private let lockMenuItem = NSMenuItem(title: "Lock", action: #selector(lockVault), keyEquivalent: "")
    private let launchAtLoginMenuItem = NSMenuItem(
        title: "Launch at Login",
        action: #selector(toggleLaunchAtLogin),
        keyEquivalent: ""
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panelController = QuickAccessPanelController(
            model: QuickAccessModel(
                session: session,
                clipboard: clipboard,
                usageStore: UsageStore(),
                openInBrowser: { NSWorkspace.shared.open($0) }
            )
        )
        self.panelController = panelController

        let hotKeyFailure: String?
        do {
            hotKey = try GlobalHotKey(
                keyCode: GlobalHotKey.quickAccessKeyCode,
                modifiers: GlobalHotKey.quickAccessModifiers
            ) {
                panelController.toggle()
            }
            hotKeyFailure = nil
        } catch {
            hotKeyFailure = "⇧⌘Space is taken by another app"
        }
        installStatusItem(hotKeyFailure: hotKeyFailure)
    }

    /// Opening the app again while it runs (from Finder, Spotlight or `open`) shows the panel; a
    /// menu bar app has no other window to bring up.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        panelController?.show()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        // A pending clear would never run once the app is gone.
        clipboard.clearIfOwnCopyIsStillThere()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        lockMenuItem.isEnabled = session.isUnlocked
        launchAtLoginMenuItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    private func installStatusItem(hotKeyFailure: String?) {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "key.horizontal.fill",
            accessibilityDescription: "Bitwarden Quick Access"
        )

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        let openMenuItem = NSMenuItem(title: "Open Quick Access", action: #selector(openQuickAccess), keyEquivalent: " ")
        openMenuItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(openMenuItem)
        if let hotKeyFailure {
            let failureMenuItem = NSMenuItem(title: hotKeyFailure, action: nil, keyEquivalent: "")
            failureMenuItem.isEnabled = false
            menu.addItem(failureMenuItem)
        }
        menu.addItem(lockMenuItem)
        menu.addItem(.separator())
        menu.addItem(launchAtLoginMenuItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        for menuItem in [openMenuItem, lockMenuItem, launchAtLoginMenuItem] {
            menuItem.target = self
        }
        statusItem.menu = menu
        self.statusItem = statusItem
    }

    @objc private func openQuickAccess() {
        panelController?.show()
    }

    @objc private func lockVault() {
        session.lock()
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Launch at Login could not be changed"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}
