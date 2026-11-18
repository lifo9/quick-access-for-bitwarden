import QuickAccessCore
import SwiftUI

struct QuickAccessView: View {
    static let panelSize = CGSize(width: 640, height: 420)
    /// The large, continuous corners of the system's own search panel.
    static let cornerRadius: CGFloat = 26
    /// Keeps the content clear of the rounded corners.
    private static let horizontalInset: CGFloat = 22
    private static let rowHeight: CGFloat = 46

    let model: QuickAccessModel
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: 58)
                .padding(.horizontal, Self.horizontalInset)
            Divider()
                .padding(.horizontal, Self.horizontalInset)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
                .padding(.horizontal, Self.horizontalInset)
            footer
                .frame(height: 34)
                .padding(.horizontal, Self.horizontalInset)
        }
        .frame(width: Self.panelSize.width, height: Self.panelSize.height)
        .overlay {
            // A hairline around the panel, which sets it apart from dark content behind it.
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(.primary.opacity(0.18), lineWidth: 1)
        }
        .onChange(of: model.focusRequestCount, initial: true) {
            isSearchFieldFocused = true
        }
    }

    // MARK: - Header

    private var header: some View {
        ZStack {
            // The search field stays in place, hidden, while the actions of an item are shown.
            // Removing it would drop the keyboard focus, and taking the focus again on the way
            // back selects the whole query, so that the next key press would replace it.
            searchField
                .opacity(model.mode == .items ? 1 : 0)
            if case .actions(let item) = model.mode {
                itemHeader(item)
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: model.session.isUnlocked ? "magnifyingglass" : "lock.fill")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 26)
            TextField(
                "Search Bitwarden",
                text: Binding(get: { model.query }, set: { model.updateQuery($0) })
            )
            .textFieldStyle(.plain)
            .font(.system(size: 22))
            .focused($isSearchFieldFocused)
            .disabled(!model.session.isUnlocked)
        }
    }

    private func itemHeader(_ item: VaultItem) -> some View {
        HStack(spacing: 12) {
            ItemIcon(kind: item.kind)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch model.session.state {
        case .locked(let explanation):
            StatusMessage(
                symbolName: "lock.fill",
                title: "Bitwarden is locked",
                detail: explanation ?? "Press Return to unlock with Touch ID."
            )
        case .unlocking:
            StatusMessage(
                symbolName: "touchid",
                title: "Unlocking…",
                detail: "Confirm the Touch ID prompt from Bitwarden."
            )
        case .unlocked(let vault):
            switch model.mode {
            case .items:
                itemList(numUndecryptableItems: vault.numUndecryptableItems)
            case .actions:
                actionList
            }
        }
    }

    @ViewBuilder
    private func itemList(numUndecryptableItems: Int) -> some View {
        // One snapshot for the row ids and the rows: a row drawn late must not index into a
        // list that has shrunk since.
        let items = model.matchingItems
        if items.isEmpty {
            StatusMessage(
                symbolName: "magnifyingglass",
                title: "No items found",
                detail: numUndecryptableItems > 0
                    ? "\(numUndecryptableItems) items use a format that is not supported."
                    : "Nothing in your vault matches “\(model.query)”."
            )
        } else {
            SelectableList(
                rowIds: items.map(\.id),
                selectedRowIndex: model.selectedItemIndex,
                rowHeight: Self.rowHeight,
                onActivate: { model.activateItem(at: $0) },
                rowContent: { itemIndex, isSelected in
                    let item = items[itemIndex]
                    HStack(spacing: 12) {
                        ItemIcon(kind: item.kind)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name)
                                .font(.system(size: 14, weight: .medium))
                                .lineLimit(1)
                            if !item.subtitle.isEmpty {
                                Text(item.subtitle)
                                    .font(.system(size: 12))
                                    .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        if item.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                        }
                    }
                }
            )
        }
    }

    private var actionList: some View {
        let actions = model.actions
        return SelectableList(
            rowIds: actions.map(\.id),
            selectedRowIndex: model.selectedActionIndex,
            rowHeight: 34,
            onActivate: { model.activateAction(at: $0) },
            rowContent: { actionIndex, isSelected in
                let action = actions[actionIndex]
                HStack {
                    Text(action.title)
                        .font(.system(size: 14))
                        .lineLimit(1)
                    Spacer()
                    if let shortcutHint = action.shortcutHint {
                        Text(shortcutHint)
                            .font(.system(size: 12))
                            .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                    }
                }
            }
        )
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 14) {
            if let notice = model.notice {
                Label(notice, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            } else {
                ForEach(footerHints, id: \.self) { hint in
                    Text(hint)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .font(.system(size: 11))
    }

    private var footerHints: [String] {
        guard model.session.isUnlocked else {
            return ["↩ Unlock"]
        }
        switch model.mode {
        case .items:
            return ["↩ Copy", "→ Actions", "⌘C Username", "⇧⌘C Password", "⌥⌘C One-time code", "⌥↩ Open website"]
        case .actions:
            return ["↩ Run", "← Back"]
        }
    }
}

/// A keyboard-driven list: the selection is drawn here and moved by the panel's key handling.
private struct SelectableList<RowContent: View>: View {
    let rowIds: [String]
    let selectedRowIndex: Int
    let rowHeight: CGFloat
    let onActivate: (Int) -> Void
    @ViewBuilder let rowContent: (_ rowIndex: Int, _ isSelected: Bool) -> RowContent

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(rowIds.enumerated()), id: \.element) { rowIndex, rowId in
                        let isSelected = rowIndex == selectedRowIndex
                        rowContent(rowIndex, isSelected)
                            .padding(.horizontal, 12)
                            .frame(height: rowHeight)
                            .foregroundStyle(isSelected ? .white : .primary)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(isSelected ? Color.accentColor : .clear)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { onActivate(rowIndex) }
                            .id(rowId)
                    }
                }
                .padding(10)
            }
            .onChange(of: selectedRowIndex) {
                guard rowIds.indices.contains(selectedRowIndex) else {
                    return
                }
                scrollProxy.scrollTo(rowIds[selectedRowIndex])
            }
        }
    }
}

private struct ItemIcon: View {
    let kind: VaultItemKind

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: 15, weight: .medium))
            .frame(width: 26, height: 26)
    }

    private var symbolName: String {
        switch kind {
        case .login: "globe"
        case .secureNote: "note.text"
        case .card: "creditcard"
        case .identity: "person.text.rectangle"
        case .sshKey: "terminal"
        }
    }
}

private struct StatusMessage: View {
    let symbolName: String
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbolName)
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.system(size: 16, weight: .semibold))
            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
    }
}
