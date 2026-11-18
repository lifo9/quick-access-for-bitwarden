import AppKit
import QuickAccessCore

/// Puts copied values on the clipboard and removes them again after the delay configured in the
/// Bitwarden desktop app.
@MainActor
final class ClipboardWriter {
    /// A marker many clipboard managers honor by not recording the entry (nspasteboard.org).
    private static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")

    private let pasteboard: NSPasteboard
    private var changeCountOfOwnCopy: Int?
    private var pendingClear: Task<Void, Never>?

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func copy(_ text: String, isConcealed: Bool, clearDelay: ClipboardClearDelay) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        if isConcealed {
            pasteboard.setString("", forType: Self.concealedType)
        }
        changeCountOfOwnCopy = pasteboard.changeCount

        pendingClear?.cancel()
        guard case .seconds(let delaySeconds) = clearDelay else {
            pendingClear = nil
            return
        }
        pendingClear = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delaySeconds))
            guard !Task.isCancelled else {
                return
            }
            self?.clearIfOwnCopyIsStillThere()
        }
    }

    /// Leaves the clipboard alone when something else was copied in the meantime.
    func clearIfOwnCopyIsStillThere() {
        guard let changeCountOfOwnCopy, pasteboard.changeCount == changeCountOfOwnCopy else {
            return
        }
        pasteboard.clearContents()
        self.changeCountOfOwnCopy = nil
    }
}
