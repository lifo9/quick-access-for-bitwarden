import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let session: VaultSession
    private let model: QuickAccessModel
    private let clipboard = ClipboardWriter()
    private var panelController: QuickAccessPanelController?
    private var hotKey: GlobalHotKey?
    private var statusItem: NSStatusItem?
    private var isHotKeyTaken = false

    private let openMenuItem = NSMenuItem(title: "", action: #selector(openQuickAccess), keyEquivalent: " ")
    private let hotKeyTakenMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let lockMenuItem = NSMenuItem(title: "", action: #selector(lockVault), keyEquivalent: "")
    private let launchAtLoginMenuItem = NSMenuItem(title: "", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private let hideIconMenuItem = NSMenuItem(title: "", action: #selector(hideMenuBarIcon), keyEquivalent: "")
    private let quitMenuItem = NSMenuItem(
        title: "", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

    init(environment: AppEnvironment) {
        session = VaultSession(desktop: environment.desktop)
        model = QuickAccessModel(
            session: session,
            iconStore: environment.iconStore,
            clipboard: clipboard,
            usageStore: UsageStore(defaults: environment.usageDefaults),
            openInBrowser: { NSWorkspace.shared.open($0) }
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let panelController = QuickAccessPanelController(model: model)
        self.panelController = panelController

        do {
            hotKey = try GlobalHotKey(
                keyCode: GlobalHotKey.quickAccessKeyCode,
                modifiers: GlobalHotKey.quickAccessModifiers
            ) {
                panelController.toggle()
            }
        } catch {
            isHotKeyTaken = true
        }
        installStatusItem()
    }

    /// Opening the app again while it runs (from Spotlight, Finder or `open`) shows the panel and
    /// brings a hidden menu bar icon back: with the icon hidden there is no other way to its menu.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        statusItem?.isVisible = true
        panelController?.show()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        // A pending clear would never run once the app is gone.
        clipboard.clearIfOwnCopyIsStillThere()
    }

    /// The menu is brought up to date each time it opens: its texts follow the language of the
    /// Bitwarden desktop app, which can change while this app runs.
    func menuNeedsUpdate(_ menu: NSMenu) {
        session.reloadIfDesktopStateChanged()
        let strings = model.strings
        openMenuItem.title = strings.menuOpenQuickAccess
        hotKeyTakenMenuItem.title = strings.hotKeyIsTaken
        hotKeyTakenMenuItem.isHidden = !isHotKeyTaken
        lockMenuItem.title = strings.menuLock
        lockMenuItem.isEnabled = session.isUnlocked
        launchAtLoginMenuItem.title = strings.menuLaunchAtLogin
        launchAtLoginMenuItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        hideIconMenuItem.title = strings.menuHideIcon
        quitMenuItem.title = strings.menuQuit
    }

    private func installStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(
            systemSymbolName: "key.horizontal.fill",
            accessibilityDescription: "Quick Access for Bitwarden"
        )
        // The system remembers under this name whether the icon is shown, and lets it be removed
        // the way other menu bar icons are, by dragging it out with the Command key held.
        statusItem.autosaveName = "QuickAccessMenuBarIcon"
        statusItem.behavior = .removalAllowed

        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        openMenuItem.keyEquivalentModifierMask = [.command, .shift]
        hotKeyTakenMenuItem.isEnabled = false
        for menuItem in [openMenuItem, lockMenuItem, launchAtLoginMenuItem, hideIconMenuItem] {
            menuItem.target = self
        }
        menu.items = [
            openMenuItem, hotKeyTakenMenuItem, lockMenuItem, .separator(),
            launchAtLoginMenuItem, hideIconMenuItem, .separator(),
            quitMenuItem,
        ]
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
            alert.messageText = model.strings.launchAtLoginCouldNotBeChanged
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    /// Asks first, because the way to get the icon back is not something to find out by trial.
    @objc private func hideMenuBarIcon() {
        let strings = model.strings
        let question = NSAlert()
        question.messageText = strings.hideIconQuestion
        question.informativeText = strings.hideIconExplanation
        question.addButton(withTitle: strings.hideIconConfirm)
        question.addButton(withTitle: strings.cancel)
        NSApp.activate()
        if question.runModal() == .alertFirstButtonReturn {
            statusItem?.isVisible = false
        }
    }
}
