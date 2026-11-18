import AppKit
import Observation
import QuickAccessCore

/// Something the user can do with the selected item.
struct ItemAction: Identifiable {
    enum Effect {
        case copy(VaultField)
        case openWebsite(VaultField)
    }

    let id: String
    let title: String
    let shortcutHint: String?
    let effect: Effect
}

/// The state and the commands of the quick access panel.
@MainActor
@Observable
final class QuickAccessModel {
    enum Mode: Equatable {
        case items
        /// The list of actions for one item, opened with the right arrow key.
        case actions(item: VaultItem)
    }

    let session: VaultSession
    private let clipboard: ClipboardWriter
    private let usageStore: UsageStore
    private let openInBrowser: (URL) -> Void

    private(set) var query = ""
    private(set) var matchingItems = [VaultItem]()
    private(set) var selectedItemIndex = 0
    private(set) var mode = Mode.items
    private(set) var selectedActionIndex = 0
    /// A short message about the last command, such as why a value could not be copied.
    private(set) var notice: String?
    /// Changes whenever the search field should take the keyboard focus.
    private(set) var focusRequestCount = 0

    private var frontmostAppName: String?
    /// Closes the panel; set by the panel controller.
    var dismissPanel: () -> Void = {}

    init(
        session: VaultSession,
        clipboard: ClipboardWriter,
        usageStore: UsageStore,
        openInBrowser: @escaping (URL) -> Void
    ) {
        self.session = session
        self.clipboard = clipboard
        self.usageStore = usageStore
        self.openInBrowser = openInBrowser
    }

    var selectedItem: VaultItem? {
        matchingItems.indices.contains(selectedItemIndex) ? matchingItems[selectedItemIndex] : nil
    }

    var actions: [ItemAction] {
        guard case .actions(let item) = mode else {
            return []
        }
        return Self.makeActions(for: item)
    }

    // MARK: - Panel lifecycle

    func prepareForShowing(frontmostAppName: String?) {
        self.frontmostAppName = frontmostAppName
        query = ""
        mode = .items
        notice = nil
        session.reloadIfDesktopStateChanged()
        refreshMatchingItems()
        focusRequestCount += 1
    }

    func unlock() async {
        await session.unlock()
        refreshMatchingItems()
        focusRequestCount += 1
    }

    // MARK: - Commands

    func updateQuery(_ newQuery: String) {
        // The search field reports its text again whenever it takes the keyboard focus. That is
        // not a new search and must not reset the selection or dismiss the notice.
        guard newQuery != query else {
            return
        }
        query = newQuery
        notice = nil
        refreshMatchingItems()
    }

    func moveSelection(by offset: Int) {
        switch mode {
        case .items:
            selectedItemIndex = Self.clamp(selectedItemIndex + offset, toCount: matchingItems.count)
        case .actions:
            selectedActionIndex = Self.clamp(selectedActionIndex + offset, toCount: actions.count)
        }
    }

    /// Return: unlocks when locked, otherwise copies the item's main secret or runs the action.
    func activateSelection() {
        guard session.isUnlocked else {
            Task { await unlock() }
            return
        }
        switch mode {
        case .items:
            guard let item = selectedItem, let defaultField = item.defaultField else {
                return
            }
            perform(.copy(defaultField), on: item)
        case .actions(let item):
            let actions = actions
            guard actions.indices.contains(selectedActionIndex) else {
                return
            }
            perform(actions[selectedActionIndex].effect, on: item)
        }
    }

    func activateItem(at itemIndex: Int) {
        guard matchingItems.indices.contains(itemIndex) else {
            return
        }
        selectedItemIndex = itemIndex
        activateSelection()
    }

    func activateAction(at actionIndex: Int) {
        selectedActionIndex = actionIndex
        activateSelection()
    }

    func showActionsOfSelectedItem() {
        guard mode == .items, let item = selectedItem else {
            return
        }
        notice = nil
        selectedActionIndex = 0
        mode = .actions(item: item)
    }

    func showItems() {
        notice = nil
        mode = .items
        focusRequestCount += 1
    }

    /// Escape: steps back from the actions, then clears the search, then closes the panel.
    func stepBack() {
        if mode != .items {
            showItems()
        } else if !query.isEmpty {
            updateQuery("")
        } else {
            dismissPanel()
        }
    }

    func copyPrimaryField() {
        copyField(of: currentItem) { $0.primaryField }
    }

    func copyPassword() {
        copyField(of: currentItem) { $0.firstField(withRole: .password) }
    }

    func copyOneTimeCode() {
        copyField(of: currentItem) { $0.firstField(withRole: .oneTimeCode) }
    }

    func openWebsite() {
        guard let item = currentItem else {
            return
        }
        guard let websiteField = item.firstField(withRole: .website) else {
            notice = "\(item.name) has no website."
            return
        }
        perform(.openWebsite(websiteField), on: item)
    }

    // MARK: - Implementation

    /// The item the keyboard shortcuts act on in either mode.
    private var currentItem: VaultItem? {
        if case .actions(let item) = mode {
            return item
        }
        return selectedItem
    }

    private func copyField(of item: VaultItem?, select: (VaultItem) -> VaultField?) {
        guard let item else {
            return
        }
        guard let field = select(item) else {
            notice = "\(item.name) has no such field."
            return
        }
        perform(.copy(field), on: item)
    }

    private func perform(_ effect: ItemAction.Effect, on item: VaultItem) {
        do {
            switch effect {
            case .copy(let field):
                let revealedValue = try item.revealValue(of: field)
                let textToCopy =
                    field.role == .oneTimeCode
                    ? TotpGenerator.generateCode(
                        configuration: try TotpConfiguration(authenticatorKey: revealedValue),
                        at: Date()
                    )
                    : revealedValue
                clipboard.copy(
                    textToCopy,
                    isConcealed: field.isConcealed,
                    clearDelay: session.settings.clipboardClearDelay
                )
            case .openWebsite(let field):
                guard let websiteUrl = Self.makeWebsiteUrl(try item.revealValue(of: field)) else {
                    notice = "This website address cannot be opened in a browser."
                    return
                }
                openInBrowser(websiteUrl)
            }
            usageStore.recordUse(ofItemWithId: item.id)
            session.noteUse()
            dismissPanel()
        } catch VaultError.masterPasswordRepromptRequired {
            notice = "This item asks for the master password again. Open it in Bitwarden."
        } catch is TotpError {
            notice = "The authenticator key of this item is not valid."
        } catch {
            notice = "This value could not be read."
        }
    }

    private func refreshMatchingItems() {
        guard case .unlocked(let vault) = session.state else {
            matchingItems = []
            selectedItemIndex = 0
            mode = .items
            return
        }
        matchingItems = VaultSearch.rank(
            items: vault.items,
            query: query,
            numUsesByItemId: usageStore.numUsesByItemId,
            frontmostAppName: frontmostAppName
        )
        selectedItemIndex = 0
    }

    private static func clamp(_ index: Int, toCount count: Int) -> Int {
        max(0, min(index, count - 1))
    }

    /// Only web addresses are opened; vault data must not be able to launch other URL schemes.
    private static func makeWebsiteUrl(_ website: String) -> URL? {
        let hasScheme = website.contains("://")
        guard let websiteUrl = URL(string: hasScheme ? website : "https://\(website)"),
            let scheme = websiteUrl.scheme?.lowercased(),
            ["http", "https"].contains(scheme),
            websiteUrl.host() != nil
        else {
            return nil
        }
        return websiteUrl
    }

    private static func makeActions(for item: VaultItem) -> [ItemAction] {
        let firstWebsiteFieldId = item.firstField(withRole: .website)?.id
        return item.fields.flatMap { field -> [ItemAction] in
            if field.role == .website {
                return [
                    ItemAction(
                        id: "open.\(field.id)",
                        title: "Open Website",
                        shortcutHint: field.id == firstWebsiteFieldId ? "⌥↩" : nil,
                        effect: .openWebsite(field)
                    ),
                    ItemAction(id: "copy.\(field.id)", title: "Copy Website", shortcutHint: nil, effect: .copy(field)),
                ]
            }
            let shortcutHint: String? =
                if field.id == item.firstField(withRole: .password)?.id {
                    "⇧⌘C"
                } else if field.id == item.firstField(withRole: .oneTimeCode)?.id {
                    "⌥⌘C"
                } else if field.id == item.primaryField?.id {
                    "⌘C"
                } else {
                    nil
                }
            return [
                ItemAction(
                    id: "copy.\(field.id)", title: "Copy \(field.label)", shortcutHint: shortcutHint,
                    effect: .copy(field))
            ]
        }
    }
}
