import Foundation
@testable import QuickAccessCore
import XCTest

final class VaultSearchTests: XCTestCase {
    private func makeItem(
        _ name: String,
        subtitle: String = "",
        websites: [String] = [],
        isFavorite: Bool = false
    ) -> VaultItem {
        VaultItem(
            id: name,
            kind: .login,
            name: name,
            subtitle: subtitle,
            websites: websites,
            isFavorite: isFavorite,
            requiresMasterPasswordReprompt: false,
            fields: []
        )
    }

    private func rank(
        _ items: [VaultItem],
        query: String,
        numUsesByItemId: [String: Int] = [:],
        frontmostAppName: String? = nil
    ) -> [String] {
        VaultSearch.rank(
            items: items,
            query: query,
            numUsesByItemId: numUsesByItemId,
            frontmostAppName: frontmostAppName
        ).map(\.name)
    }

    func test_rank__prefersNamePrefixOverWordPrefixOverSubstring() {
        let items = [makeItem("Bigit"), makeItem("My GitHub"), makeItem("GitLab")]

        XCTAssertEqual(rank(items, query: "git"), ["GitLab", "My GitHub", "Bigit"])
    }

    func test_rank__matchesUsernameAndWebsiteAfterName() {
        let items = [
            makeItem("Forum", websites: ["https://alice.example.org"]),
            makeItem("Mail", subtitle: "alice@example.com"),
            makeItem("Alice's bank"),
            makeItem("Unrelated", subtitle: "bob"),
        ]

        XCTAssertEqual(rank(items, query: "alice"), ["Alice's bank", "Mail", "Forum"])
    }

    func test_rank__requiresEveryWordOfTheQuery() {
        let items = [
            makeItem("GitHub", subtitle: "work@example.com"),
            makeItem("GitHub personal", subtitle: "me@example.com"),
        ]

        XCTAssertEqual(rank(items, query: "github work"), ["GitHub"])
    }

    func test_rank__ignoresCaseAndDiacritics() {
        let items = [makeItem("Poštová banka")]

        XCTAssertEqual(rank(items, query: "POSTOVA"), ["Poštová banka"])
    }

    func test_rank__breaksTiesByUsageThenFavoriteThenName() {
        let items = [
            makeItem("Git beta"),
            makeItem("Git alpha"),
            makeItem("Git favorite", isFavorite: true),
            makeItem("Git often used"),
        ]

        XCTAssertEqual(
            rank(items, query: "git", numUsesByItemId: ["Git often used": 5]),
            ["Git often used", "Git favorite", "Git alpha", "Git beta"]
        )
    }

    func test_rank__suggestsItemsOfFrontmostAppThenMostUsedWhenQueryIsEmpty() {
        let items = [makeItem("Amazon"), makeItem("Slack workspace"), makeItem("Bank"), makeItem("Zoo")]

        XCTAssertEqual(
            rank(items, query: "  ", numUsesByItemId: ["Zoo": 3, "Bank": 1], frontmostAppName: "Slack"),
            ["Slack workspace", "Zoo", "Bank", "Amazon"]
        )
    }
}
