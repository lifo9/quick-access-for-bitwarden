import Foundation
import QuickAccessCore

/// The languages the app has its texts in.
enum AppLanguage: Equatable, CaseIterable {
    case english
    case slovak
    case czech

    /// The language the Bitwarden desktop app is set to, or, when it follows the system, the
    /// system's first language. Languages without texts of their own get English.
    ///
    /// - Parameters:
    ///   - desktopLocale: The locale stored by the desktop app, such as `sk` or `en-GB`; `nil`
    ///     when it follows the system.
    ///   - preferredSystemLanguages: The system's languages in order of preference.
    static func resolve(desktopLocale: String?, preferredSystemLanguages: [String]) -> AppLanguage {
        let locale = desktopLocale ?? preferredSystemLanguages.first ?? "en"
        let languageCode = locale.lowercased().split { $0 == "-" || $0 == "_" }.first.map(String.init)
        switch languageCode {
        case "sk": return .slovak
        case "cs": return .czech
        default: return .english
        }
    }
}

/// Every text the app shows, in one language. The Slovak and Czech wording of terms the Bitwarden
/// desktop app also has (field names, "trezor", "hlavné heslo") is taken from its translations.
struct AppStrings: Sendable {
    // The panel
    let searchPlaceholder: String
    let lockedTitle: String
    let lockedHint: String
    let unlockingTitle: String
    let unlockingHint: String
    let noItemsTitle: String
    let nothingMatches: @Sendable (_ query: String) -> String
    let unsupportedItems: @Sendable (_ numItems: Int) -> String

    // The footer: what the keys do
    let hintCopy: String
    let hintActions: String
    let hintUsername: String
    let hintPassword: String
    let hintOneTimeCode: String
    let hintOpenWebsite: String
    let hintUnlock: String
    let hintRun: String
    let hintBack: String

    // The actions of an item
    let copyField: @Sendable (_ fieldName: String) -> String
    let openWebsite: String
    let unnamedCustomField: @Sendable (_ fieldNumber: Int) -> String

    // Why a command did nothing
    let itemHasNoWebsite: @Sendable (_ itemName: String) -> String
    let itemHasNoSuchField: @Sendable (_ itemName: String) -> String
    let websiteCannotBeOpened: String
    let masterPasswordRepromptRequired: String
    let authenticatorKeyIsNotValid: String
    let valueCouldNotBeRead: String

    // Why the vault stays locked
    let touchIdWasCancelled: String
    let masterPasswordNeededFirst: String
    let touchIdSwitchedOffInBitwarden: String
    let touchIdNotAvailable: String
    let cannotUnlockWithTouchId: @Sendable (_ status: String) -> String
    let desktopAppNotInstalled: String
    let noAccountLoggedIn: String
    let unsupportedAccountEncryption: String
    let desktopAppDidNotAnswer: String
    let desktopAppUsesAnotherAccount: String
    let keyOfAnotherAccount: String
    let unlockingFailed: @Sendable (_ reason: String) -> String

    // The menu of the menu bar icon
    let menuOpenQuickAccess: String
    let menuLock: String
    let menuLaunchAtLogin: String
    let menuQuit: String
    let hotKeyIsTaken: String
    let launchAtLoginCouldNotBeChanged: String
    let menuHideIcon: String
    let hideIconQuestion: String
    let hideIconExplanation: String
    let hideIconConfirm: String
    let cancel: String

    /// The names of an item's fields, by what the field holds.
    let fieldNames: [VaultFieldName: String]

    static func strings(for language: AppLanguage) -> AppStrings {
        switch language {
        case .english: english
        case .slovak: slovak
        case .czech: czech
        }
    }

    /// The name shown for a field: the user's own name for a custom field, else the translation.
    func name(of fieldName: VaultFieldName) -> String {
        switch fieldName {
        case .custom(let customName):
            customName
        case .unnamedCustom(let fieldNumber):
            unnamedCustomField(fieldNumber)
        default:
            // Every other name has a translation; the English one is a safety net.
            fieldNames[fieldName] ?? AppStrings.english.fieldNames[fieldName] ?? ""
        }
    }

    /// What an action of an item is called in its list.
    func title(of action: ItemAction) -> String {
        switch action.effect {
        case .copy(let field): copyField(name(of: field.name))
        case .openWebsite: openWebsite
        }
    }

    func text(of notice: PanelNotice) -> String {
        switch notice {
        case .itemHasNoWebsite(let itemName): itemHasNoWebsite(itemName)
        case .itemHasNoSuchField(let itemName): itemHasNoSuchField(itemName)
        case .websiteCannotBeOpened: websiteCannotBeOpened
        case .masterPasswordRepromptRequired: masterPasswordRepromptRequired
        case .authenticatorKeyIsNotValid: authenticatorKeyIsNotValid
        case .valueCouldNotBeRead: valueCouldNotBeRead
        }
    }

    func text(of failure: UnlockFailure) -> String {
        switch failure {
        case .touchIdWasCancelled: touchIdWasCancelled
        case .masterPasswordNeededFirst: masterPasswordNeededFirst
        case .touchIdSwitchedOffInBitwarden: touchIdSwitchedOffInBitwarden
        case .touchIdNotAvailable: touchIdNotAvailable
        case .cannotUnlockWithTouchId(let status): cannotUnlockWithTouchId(status)
        case .desktopAppNotInstalled: desktopAppNotInstalled
        case .noAccountLoggedIn: noAccountLoggedIn
        case .unsupportedAccountEncryption: unsupportedAccountEncryption
        case .desktopAppDidNotAnswer: desktopAppDidNotAnswer
        case .desktopAppUsesAnotherAccount: desktopAppUsesAnotherAccount
        case .keyOfAnotherAccount: keyOfAnotherAccount
        case .other(let description): unlockingFailed(description)
        }
    }

    static let english = AppStrings(
        searchPlaceholder: "Search Bitwarden",
        lockedTitle: "Bitwarden is locked",
        lockedHint: "Press Return to unlock with Touch ID.",
        unlockingTitle: "Unlocking…",
        unlockingHint: "Confirm the Touch ID prompt from Bitwarden.",
        noItemsTitle: "No items found",
        nothingMatches: { "Nothing in your vault matches “\($0)”." },
        unsupportedItems: { "\($0) items use a format that is not supported." },
        hintCopy: "↩ Copy",
        hintActions: "→ Actions",
        hintUsername: "⌘C Username",
        hintPassword: "⇧⌘C Password",
        hintOneTimeCode: "⌥⌘C One-time code",
        hintOpenWebsite: "⌥↩ Open website",
        hintUnlock: "↩ Unlock",
        hintRun: "↩ Run",
        hintBack: "← Back",
        copyField: { "Copy \($0)" },
        openWebsite: "Open Website",
        unnamedCustomField: { "Field \($0)" },
        itemHasNoWebsite: { "\($0) has no website." },
        itemHasNoSuchField: { "\($0) has no such field." },
        websiteCannotBeOpened: "This website address cannot be opened in a browser.",
        masterPasswordRepromptRequired: "This item asks for the master password again. Open it in Bitwarden.",
        authenticatorKeyIsNotValid: "The authenticator key of this item is not valid.",
        valueCouldNotBeRead: "This value could not be read.",
        touchIdWasCancelled: "Touch ID was cancelled.",
        masterPasswordNeededFirst:
            "Bitwarden needs your master password once after it starts. Unlock Bitwarden, then try again.",
        touchIdSwitchedOffInBitwarden: "Unlock with Touch ID is switched off in Bitwarden's settings.",
        touchIdNotAvailable: "Touch ID is not available right now.",
        cannotUnlockWithTouchId: { "Bitwarden cannot unlock with Touch ID right now (\($0))." },
        desktopAppNotInstalled: "The Bitwarden desktop app is not installed.",
        noAccountLoggedIn: "No account is logged in to the Bitwarden desktop app.",
        unsupportedAccountEncryption: "This account uses a newer encryption format that is not supported yet.",
        desktopAppDidNotAnswer: "Bitwarden did not answer. Check that the desktop app is running.",
        desktopAppUsesAnotherAccount: "The Bitwarden desktop app is logged in to a different account.",
        keyOfAnotherAccount: "Bitwarden handed over a key for a different account. Try again.",
        unlockingFailed: { "Unlocking failed: \($0)" },
        menuOpenQuickAccess: "Open Quick Access",
        menuLock: "Lock",
        menuLaunchAtLogin: "Launch at Login",
        menuQuit: "Quit",
        hotKeyIsTaken: "⇧⌘Space is taken by another app",
        launchAtLoginCouldNotBeChanged: "Launch at Login could not be changed",
        menuHideIcon: "Hide Menu Bar Icon…",
        hideIconQuestion: "Hide the menu bar icon?",
        hideIconExplanation:
            "⇧⌘Space keeps opening the panel. To get the icon back, open Quick Access for Bitwarden again, "
            + "from Spotlight or the Applications folder.",
        hideIconConfirm: "Hide",
        cancel: "Cancel",
        fieldNames: [
            .username: "Username",
            .password: "Password",
            .oneTimeCode: "One-time code",
            .website: "Website",
            .notes: "Notes",
            .cardNumber: "Number",
            .cardSecurityCode: "Security code",
            .cardholderName: "Cardholder name",
            .cardExpirationMonth: "Expiration month",
            .cardExpirationYear: "Expiration year",
            .cardBrand: "Brand",
            .identityEmail: "Email",
            .identityUsername: "Username",
            .identityPhone: "Phone",
            .identityTitle: "Title",
            .identityFirstName: "First name",
            .identityMiddleName: "Middle name",
            .identityLastName: "Last name",
            .identityCompany: "Company",
            .identityAddress1: "Address 1",
            .identityAddress2: "Address 2",
            .identityAddress3: "Address 3",
            .identityCity: "City",
            .identityState: "State",
            .identityPostalCode: "Postal code",
            .identityCountry: "Country",
            .identitySocialSecurityNumber: "Social security number",
            .identityPassportNumber: "Passport number",
            .identityLicenseNumber: "License number",
            .sshPublicKey: "Public key",
            .sshKeyFingerprint: "Fingerprint",
            .sshPrivateKey: "Private key",
        ]
    )

    static let slovak = AppStrings(
        searchPlaceholder: "Hľadať v trezore",
        lockedTitle: "Trezor je uzamknutý",
        lockedHint: "Stlačením klávesu Return ho odomknete pomocou Touch ID.",
        unlockingTitle: "Odomyká sa…",
        unlockingHint: "Potvrďte výzvu Touch ID z aplikácie Bitwarden.",
        noItemsTitle: "Nenašli sa žiadne položky",
        nothingMatches: { "V trezore nič nezodpovedá výrazu „\($0)“." },
        unsupportedItems: { "Počet položiek v nepodporovanom formáte: \($0)." },
        hintCopy: "↩ Kopírovať",
        hintActions: "→ Akcie",
        hintUsername: "⌘C Meno",
        hintPassword: "⇧⌘C Heslo",
        hintOneTimeCode: "⌥⌘C Overovací kód",
        hintOpenWebsite: "⌥↩ Otvoriť web",
        hintUnlock: "↩ Odomknúť",
        hintRun: "↩ Spustiť",
        hintBack: "← Späť",
        // With a colon, so that the field's name stays in the form it is listed in.
        copyField: { "Kopírovať: \($0)" },
        openWebsite: "Otvoriť webstránku",
        unnamedCustomField: { "Pole \($0)" },
        itemHasNoWebsite: { "Položka \($0) nemá webstránku." },
        itemHasNoSuchField: { "Položka \($0) také pole nemá." },
        websiteCannotBeOpened: "Túto adresu nemožno otvoriť v prehliadači.",
        masterPasswordRepromptRequired:
            "Táto položka vyžaduje opätovné zadanie hlavného hesla. Otvorte ju v Bitwardene.",
        authenticatorKeyIsNotValid: "Kľúč overovacieho kódu tejto položky nie je platný.",
        valueCouldNotBeRead: "Túto hodnotu sa nepodarilo prečítať.",
        touchIdWasCancelled: "Overenie cez Touch ID bolo zrušené.",
        masterPasswordNeededFirst:
            "Bitwarden po spustení potrebuje raz vaše hlavné heslo. Odomknite Bitwarden a skúste to znova.",
        touchIdSwitchedOffInBitwarden: "Odomykanie pomocou Touch ID je v nastaveniach Bitwardenu vypnuté.",
        touchIdNotAvailable: "Touch ID momentálne nie je k dispozícii.",
        cannotUnlockWithTouchId: { "Bitwarden momentálne nemôže odomknúť pomocou Touch ID (\($0))." },
        desktopAppNotInstalled: "Aplikácia Bitwarden pre počítač nie je nainštalovaná.",
        noAccountLoggedIn: "V aplikácii Bitwarden nie je prihlásený žiadny účet.",
        unsupportedAccountEncryption: "Tento účet používa novší formát šifrovania, ktorý zatiaľ nie je podporovaný.",
        desktopAppDidNotAnswer: "Bitwarden neodpovedal. Skontrolujte, či je aplikácia spustená.",
        desktopAppUsesAnotherAccount: "Aplikácia Bitwarden je prihlásená do iného účtu.",
        keyOfAnotherAccount: "Bitwarden odovzdal kľúč iného účtu. Skúste to znova.",
        unlockingFailed: { "Odomknutie zlyhalo: \($0)" },
        menuOpenQuickAccess: "Otvoriť rýchly prístup",
        menuLock: "Zamknúť trezor",
        menuLaunchAtLogin: "Spustiť po prihlásení",
        menuQuit: "Ukončiť",
        hotKeyIsTaken: "Skratku ⇧⌘Medzerník používa iná aplikácia",
        launchAtLoginCouldNotBeChanged: "Spúšťanie po prihlásení sa nepodarilo zmeniť",
        menuHideIcon: "Skryť ikonu v lište…",
        hideIconQuestion: "Skryť ikonu v lište?",
        hideIconExplanation:
            "Skratka ⇧⌘Medzerník bude panel otvárať aj naďalej. Ikonu vrátite tak, že aplikáciu "
            + "Quick Access for Bitwarden otvoríte znova, cez Spotlight alebo z priečinka Aplikácie.",
        hideIconConfirm: "Skryť",
        cancel: "Zrušiť",
        fieldNames: [
            .username: "Používateľské meno",
            .password: "Heslo",
            .oneTimeCode: "Overovací kód (TOTP)",
            .website: "Webstránka",
            .notes: "Poznámky",
            .cardNumber: "Číslo",
            .cardSecurityCode: "Bezpečnostný kód",
            .cardholderName: "Meno vlastníka karty",
            .cardExpirationMonth: "Mesiac exspirácie",
            .cardExpirationYear: "Rok exspirácie",
            .cardBrand: "Značka",
            .identityEmail: "E-mail",
            .identityUsername: "Používateľské meno",
            .identityPhone: "Telefón",
            .identityTitle: "Oslovenie",
            .identityFirstName: "Krstné meno",
            .identityMiddleName: "Stredné meno",
            .identityLastName: "Priezvisko",
            .identityCompany: "Spoločnosť",
            .identityAddress1: "Adresa 1",
            .identityAddress2: "Adresa 2",
            .identityAddress3: "Adresa 3",
            .identityCity: "Mesto",
            .identityState: "Región",
            .identityPostalCode: "PSČ",
            .identityCountry: "Krajina",
            .identitySocialSecurityNumber: "Číslo poistenca sociálnej poisťovne",
            .identityPassportNumber: "Číslo pasu",
            .identityLicenseNumber: "Číslo vodičského preukazu",
            .sshPublicKey: "Verejný kľúč",
            .sshKeyFingerprint: "Odtlačok",
            .sshPrivateKey: "Súkromný kľúč",
        ]
    )

    static let czech = AppStrings(
        searchPlaceholder: "Hledat v trezoru",
        lockedTitle: "Trezor je uzamčen",
        lockedHint: "Stisknutím klávesy Return jej odemknete pomocí Touch ID.",
        unlockingTitle: "Odemyká se…",
        unlockingHint: "Potvrďte výzvu Touch ID z aplikace Bitwarden.",
        noItemsTitle: "Nebyly nalezeny žádné položky",
        nothingMatches: { "V trezoru nic neodpovídá výrazu „\($0)“." },
        unsupportedItems: { "Počet položek v nepodporovaném formátu: \($0)." },
        hintCopy: "↩ Kopírovat",
        hintActions: "→ Akce",
        hintUsername: "⌘C Jméno",
        hintPassword: "⇧⌘C Heslo",
        hintOneTimeCode: "⌥⌘C Ověřovací kód",
        hintOpenWebsite: "⌥↩ Otevřít web",
        hintUnlock: "↩ Odemknout",
        hintRun: "↩ Spustit",
        hintBack: "← Zpět",
        // With a colon, so that the field's name stays in the form it is listed in.
        copyField: { "Kopírovat: \($0)" },
        openWebsite: "Otevřít webovou stránku",
        unnamedCustomField: { "Pole \($0)" },
        itemHasNoWebsite: { "Položka \($0) nemá webovou stránku." },
        itemHasNoSuchField: { "Položka \($0) takové pole nemá." },
        websiteCannotBeOpened: "Tuto adresu nelze otevřít v prohlížeči.",
        masterPasswordRepromptRequired:
            "Tato položka vyžaduje opětovné zadání hlavního hesla. Otevřete ji v Bitwardenu.",
        authenticatorKeyIsNotValid: "Klíč ověřovacího kódu této položky není platný.",
        valueCouldNotBeRead: "Tuto hodnotu se nepodařilo přečíst.",
        touchIdWasCancelled: "Ověření přes Touch ID bylo zrušeno.",
        masterPasswordNeededFirst:
            "Bitwarden po spuštění potřebuje jednou vaše hlavní heslo. Odemkněte Bitwarden a zkuste to znovu.",
        touchIdSwitchedOffInBitwarden: "Odemykání pomocí Touch ID je v nastavení Bitwardenu vypnuté.",
        touchIdNotAvailable: "Touch ID momentálně není k dispozici.",
        cannotUnlockWithTouchId: { "Bitwarden momentálně nemůže odemknout pomocí Touch ID (\($0))." },
        desktopAppNotInstalled: "Aplikace Bitwarden pro počítač není nainstalována.",
        noAccountLoggedIn: "V aplikaci Bitwarden není přihlášen žádný účet.",
        unsupportedAccountEncryption: "Tento účet používá novější formát šifrování, který zatím není podporován.",
        desktopAppDidNotAnswer: "Bitwarden neodpověděl. Zkontrolujte, zda je aplikace spuštěná.",
        desktopAppUsesAnotherAccount: "Aplikace Bitwarden je přihlášena k jinému účtu.",
        keyOfAnotherAccount: "Bitwarden předal klíč jiného účtu. Zkuste to znovu.",
        unlockingFailed: { "Odemknutí selhalo: \($0)" },
        menuOpenQuickAccess: "Otevřít rychlý přístup",
        menuLock: "Uzamknout trezor",
        menuLaunchAtLogin: "Spustit při přihlášení",
        menuQuit: "Ukončit",
        hotKeyIsTaken: "Zkratku ⇧⌘Mezerník používá jiná aplikace",
        launchAtLoginCouldNotBeChanged: "Spouštění při přihlášení se nepodařilo změnit",
        menuHideIcon: "Skrýt ikonu v řádku nabídek…",
        hideIconQuestion: "Skrýt ikonu v řádku nabídek?",
        hideIconExplanation:
            "Zkratka ⇧⌘Mezerník bude panel otevírat i nadále. Ikonu vrátíte tak, že aplikaci "
            + "Quick Access for Bitwarden otevřete znovu, přes Spotlight nebo ze složky Aplikace.",
        hideIconConfirm: "Skrýt",
        cancel: "Zrušit",
        fieldNames: [
            .username: "Uživatelské jméno",
            .password: "Heslo",
            .oneTimeCode: "Ověřovací kód (TOTP)",
            .website: "Webová stránka",
            .notes: "Poznámky",
            .cardNumber: "Číslo",
            .cardSecurityCode: "Bezpečnostní kód",
            .cardholderName: "Jméno držitele karty",
            .cardExpirationMonth: "Měsíc expirace",
            .cardExpirationYear: "Rok expirace",
            .cardBrand: "Značka",
            .identityEmail: "E-mail",
            .identityUsername: "Uživatelské jméno",
            .identityPhone: "Telefon",
            .identityTitle: "Oslovení",
            .identityFirstName: "Křestní jméno",
            .identityMiddleName: "Prostřední jméno",
            .identityLastName: "Příjmení",
            .identityCompany: "Společnost",
            .identityAddress1: "Adresa 1",
            .identityAddress2: "Adresa 2",
            .identityAddress3: "Adresa 3",
            .identityCity: "Město",
            .identityState: "Kraj",
            .identityPostalCode: "PSČ",
            .identityCountry: "Stát",
            .identitySocialSecurityNumber: "Číslo sociálního pojištění",
            .identityPassportNumber: "Číslo cestovního pasu",
            .identityLicenseNumber: "Číslo řidičského průkazu",
            .sshPublicKey: "Veřejný klíč",
            .sshKeyFingerprint: "Otisk",
            .sshPrivateKey: "Soukromý klíč",
        ]
    )
}
