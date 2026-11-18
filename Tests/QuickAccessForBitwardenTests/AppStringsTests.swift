import QuickAccessCore
import XCTest

@testable import QuickAccessForBitwarden

final class AppStringsTests: XCTestCase {
    func test_resolve__takesTheDesktopAppsLanguageWhenItIsSet() {
        XCTAssertEqual(AppLanguage.resolve(desktopLocale: "sk", preferredSystemLanguages: ["en-US"]), .slovak)
        XCTAssertEqual(AppLanguage.resolve(desktopLocale: "cs", preferredSystemLanguages: ["en-US"]), .czech)
        XCTAssertEqual(AppLanguage.resolve(desktopLocale: "en-GB", preferredSystemLanguages: ["sk-SK"]), .english)
    }

    func test_resolve__takesTheSystemsFirstLanguageWhenTheDesktopAppFollowsTheSystem() {
        XCTAssertEqual(AppLanguage.resolve(desktopLocale: nil, preferredSystemLanguages: ["sk-SK", "en-US"]), .slovak)
        XCTAssertEqual(AppLanguage.resolve(desktopLocale: nil, preferredSystemLanguages: ["cs_CZ"]), .czech)
        // The first language decides; Slovak further down the list is not what the Mac is shown in.
        XCTAssertEqual(AppLanguage.resolve(desktopLocale: nil, preferredSystemLanguages: ["en-US", "sk-SK"]), .english)
    }

    func test_resolve__fallsBackToEnglishForLanguagesWithoutTexts() {
        XCTAssertEqual(AppLanguage.resolve(desktopLocale: "de", preferredSystemLanguages: ["sk-SK"]), .english)
        XCTAssertEqual(AppLanguage.resolve(desktopLocale: nil, preferredSystemLanguages: ["fr-FR"]), .english)
        XCTAssertEqual(AppLanguage.resolve(desktopLocale: nil, preferredSystemLanguages: []), .english)
    }

    func test_name__hasATextForEveryFieldInEveryLanguage() {
        for language in AppLanguage.allCases {
            let strings = AppStrings.strings(for: language)
            XCTAssertEqual(
                Set(strings.fieldNames.keys), Set(VaultFieldName.standardNames), "field names of \(language)")
            for fieldName in VaultFieldName.standardNames {
                XCTAssertFalse(strings.name(of: fieldName).isEmpty, "\(fieldName) in \(language)")
            }
        }
    }

    func test_name__keepsTheUsersOwnNameOfACustomFieldAndNumbersUnnamedOnes() {
        XCTAssertEqual(AppStrings.slovak.name(of: .custom("PIN do banky")), "PIN do banky")
        XCTAssertEqual(AppStrings.slovak.name(of: .unnamedCustom(2)), "Pole 2")
        XCTAssertEqual(AppStrings.english.name(of: .unnamedCustom(2)), "Field 2")
    }
}
