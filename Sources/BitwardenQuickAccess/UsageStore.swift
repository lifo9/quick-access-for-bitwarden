import Foundation

/// Remembers how often each item was used, to suggest the most used ones first. Holds item ids
/// and counts only, nothing from inside the vault.
@MainActor
final class UsageStore {
    private static let defaultsKey = "numUsesByItemId"

    private let defaults: UserDefaults
    private(set) var numUsesByItemId: [String: Int]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        numUsesByItemId = defaults.dictionary(forKey: Self.defaultsKey) as? [String: Int] ?? [:]
    }

    func recordUse(ofItemWithId itemId: String) {
        numUsesByItemId[itemId, default: 0] += 1
        defaults.set(numUsesByItemId, forKey: Self.defaultsKey)
    }
}
