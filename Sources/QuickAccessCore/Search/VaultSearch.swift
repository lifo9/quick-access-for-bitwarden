import Foundation

/// Orders vault items for the quick access list.
public enum VaultSearch {
    /// With an empty query this returns every item as suggestions: items named after the app in
    /// front first, then the most used, then favorites. With a query it returns the items in
    /// which every word of the query occurs, best match first.
    public static func rank(
        items: [VaultItem],
        query: String,
        numUsesByItemId: [String: Int],
        frontmostAppName: String?
    ) -> [VaultItem] {
        let queryWords = normalize(query).split(separator: " ").map(String.init)
        let normalizedAppName = frontmostAppName.map(normalize) ?? ""

        let scoredItems: [(item: VaultItem, score: Int)] = items.compactMap { item in
            let searchableItem = SearchableItem(item)
            if queryWords.isEmpty {
                let isNamedAfterFrontmostApp =
                    !normalizedAppName.isEmpty
                    && searchableItem.name.contains(normalizedAppName)
                return (item, isNamedAfterFrontmostApp ? 1 : 0)
            }
            let wordScores = queryWords.map(searchableItem.score(forQueryWord:))
            guard !wordScores.contains(0) else {
                return nil
            }
            return (item, wordScores.reduce(0, +))
        }

        let rankedItems = scoredItems.sorted { first, second in
            let firstSortKey = (first.score, numUsesByItemId[first.item.id] ?? 0, first.item.isFavorite ? 1 : 0)
            let secondSortKey = (second.score, numUsesByItemId[second.item.id] ?? 0, second.item.isFavorite ? 1 : 0)
            if firstSortKey != secondSortKey {
                return firstSortKey > secondSortKey
            }
            // The id breaks ties between items of the same name, to keep the order stable.
            return (normalize(first.item.name), first.item.id) < (normalize(second.item.name), second.item.id)
        }
        return rankedItems.map(\.item)
    }

    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespaces)
    }

    private struct SearchableItem {
        let name: String
        let nameWords: [Substring]
        let subtitle: String
        let websites: [String]

        init(_ item: VaultItem) {
            name = VaultSearch.normalize(item.name)
            nameWords = name.split { !$0.isLetter && !$0.isNumber }
            subtitle = VaultSearch.normalize(item.subtitle)
            websites = item.websites.map(VaultSearch.normalize)
        }

        /// Zero means the word does not occur in the item at all.
        func score(forQueryWord queryWord: String) -> Int {
            if name.hasPrefix(queryWord) {
                100
            } else if nameWords.contains(where: { $0.hasPrefix(queryWord) }) {
                80
            } else if name.contains(queryWord) {
                60
            } else if subtitle.hasPrefix(queryWord) {
                40
            } else if subtitle.contains(queryWord) {
                30
            } else if websites.contains(where: { $0.contains(queryWord) }) {
                20
            } else {
                0
            }
        }
    }
}
