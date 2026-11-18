import Foundation

/// Turns the encrypted desktop state into a searchable vault, given the account's user key.
///
/// Key hierarchy: the user key decrypts the account's RSA private key and personal items; the
/// private key unwraps each organization key; an item may carry its own key, wrapped by the user
/// key or by its organization's key.
public enum VaultDecryptor {
    public static func unlock(_ state: DesktopState, userKey: SymmetricCryptoKey) throws -> UnlockedVault {
        let privateKey = try decryptPrivateKey(state.encryptedPrivateKey, userKey: userKey)
        let organizationKeysByOrganizationId = state.organizationKeysByOrganizationId
            .compactMapValues { try? unwrapOrganizationKey($0, privateKey: privateKey) }

        let visibleCiphers = state.ciphers.filter { $0.deletedDate == nil && $0.archivedDate == nil }
        let items = visibleCiphers.compactMap { cipher in
            try? decryptItem(
                cipher,
                userKey: userKey,
                organizationKeysByOrganizationId: organizationKeysByOrganizationId
            )
        }
        return UnlockedVault(items: items, numUndecryptableItems: visibleCiphers.count - items.count)
    }

    private static func decryptPrivateKey(
        _ encryptedPrivateKey: String,
        userKey: SymmetricCryptoKey
    ) throws -> RsaPrivateKey {
        let pkcs8PrivateKey: Data
        do {
            pkcs8PrivateKey = try SymmetricCipher.decrypt(
                EncryptedString(serialized: encryptedPrivateKey),
                with: userKey
            )
        } catch CryptoError.authenticationFailed {
            // The private key is the one value every account has, which makes it the check that
            // the key handed over by the desktop app belongs to the account in the state file.
            throw VaultError.userKeyDoesNotMatchAccount
        }
        return try RsaCipher.makePrivateKey(pkcs8DerEncoded: pkcs8PrivateKey)
    }

    private static func unwrapOrganizationKey(
        _ organizationKey: EncryptedOrganizationKey,
        privateKey: RsaPrivateKey
    ) throws -> SymmetricCryptoKey {
        // Keys of type "provider" are wrapped by a provider key instead; no support for those.
        guard organizationKey.type == "organization", let wrappedKey = organizationKey.key else {
            throw VaultError.missingOrganizationKey
        }
        let encodedKey = try RsaCipher.decrypt(EncryptedString(serialized: wrappedKey), with: privateKey)
        return try SymmetricCryptoKey(encodedKey: encodedKey)
    }

    private static func decryptItem(
        _ cipher: EncryptedCipher,
        userKey: SymmetricCryptoKey,
        organizationKeysByOrganizationId: [String: SymmetricCryptoKey]
    ) throws -> VaultItem {
        let itemKey = try resolveItemKey(
            cipher,
            userKey: userKey,
            organizationKeysByOrganizationId: organizationKeysByOrganizationId
        )
        let builder = FieldBuilder(itemKey: itemKey)

        let kind: VaultItemKind
        let kindFields: [VaultField]
        let subtitle: String
        switch cipher.type {
        case 1:
            kind = .login
            kindFields = try makeLoginFields(cipher, builder: builder)
            subtitle = try builder.decryptText(cipher.login?.username) ?? ""
        case 2:
            kind = .secureNote
            kindFields = []
            subtitle = ""
        case 3:
            kind = .card
            kindFields = try makeCardFields(cipher.card, builder: builder)
            subtitle = try builder.decryptText(cipher.card?.brand) ?? ""
        case 4:
            kind = .identity
            kindFields = try makeIdentityFields(cipher.identity ?? [:], builder: builder)
            let nameParts = try ["firstName", "lastName"].compactMap { propertyName in
                try builder.decryptText(cipher.identity?[propertyName] ?? nil)
            }
            subtitle = nameParts.joined(separator: " ")
        case 5:
            kind = .sshKey
            kindFields = try makeSshKeyFields(cipher.sshKey, builder: builder)
            subtitle = try builder.decryptText(cipher.sshKey?.keyFingerprint) ?? ""
        default:
            throw VaultError.unsupportedItemType(cipher.type)
        }

        let noteField = try builder.makeField(id: "notes", label: "Notes", role: .note, cipher.notes)
        let fields = kindFields + [noteField].compactMap { $0 } + (try makeCustomFields(cipher.fields ?? [], builder: builder))
        let websites = try fields
            .filter { $0.role == .website }
            .map { try SymmetricCipher.decryptString($0.encryptedValue, with: itemKey) }

        return VaultItem(
            id: cipher.id,
            kind: kind,
            name: try builder.decryptText(cipher.name) ?? "",
            subtitle: subtitle,
            websites: websites,
            isFavorite: cipher.favorite ?? false,
            requiresMasterPasswordReprompt: (cipher.reprompt ?? 0) != 0,
            fields: fields
        )
    }

    private static func resolveItemKey(
        _ cipher: EncryptedCipher,
        userKey: SymmetricCryptoKey,
        organizationKeysByOrganizationId: [String: SymmetricCryptoKey]
    ) throws -> SymmetricCryptoKey {
        let ownerKey: SymmetricCryptoKey
        if let organizationId = cipher.organizationId {
            guard let organizationKey = organizationKeysByOrganizationId[organizationId] else {
                throw VaultError.missingOrganizationKey
            }
            ownerKey = organizationKey
        } else {
            ownerKey = userKey
        }
        guard let wrappedItemKey = cipher.key else {
            return ownerKey
        }
        let encodedItemKey = try SymmetricCipher.decrypt(EncryptedString(serialized: wrappedItemKey), with: ownerKey)
        return try SymmetricCryptoKey(encodedKey: encodedItemKey)
    }

    private static func makeLoginFields(_ cipher: EncryptedCipher, builder: FieldBuilder) throws -> [VaultField] {
        guard let login = cipher.login else {
            return []
        }
        // Members without the "view password" permission must not get at the secrets of a shared
        // item; the desktop app withholds the same two values.
        let canViewPassword = cipher.viewPassword ?? true
        let secretFields = canViewPassword
            ? [
                try builder.makeField(id: "login.password", label: "Password", role: .password, isConcealed: true, login.password),
                try builder.makeField(id: "login.totp", label: "One-time code", role: .oneTimeCode, isConcealed: true, login.totp),
            ]
            : []
        let websiteFields = try (login.uris ?? []).enumerated().map { uriIndex, loginUri in
            try builder.makeField(id: "login.uri.\(uriIndex)", label: "Website", role: .website, loginUri.uri)
        }
        let usernameField = try builder.makeField(id: "login.username", label: "Username", role: .username, login.username)
        return ([usernameField] + secretFields + websiteFields).compactMap { $0 }
    }

    private static func makeCardFields(_ card: EncryptedCard?, builder: FieldBuilder) throws -> [VaultField] {
        guard let card else {
            return []
        }
        return try [
            builder.makeField(id: "card.number", label: "Number", role: .cardNumber, isConcealed: true, card.number),
            builder.makeField(id: "card.code", label: "Security code", isConcealed: true, card.code),
            builder.makeField(id: "card.cardholderName", label: "Cardholder name", card.cardholderName),
            builder.makeField(id: "card.expMonth", label: "Expiration month", card.expMonth),
            builder.makeField(id: "card.expYear", label: "Expiration year", card.expYear),
            builder.makeField(id: "card.brand", label: "Brand", card.brand),
        ].compactMap { $0 }
    }

    private static let identityProperties: [(propertyName: String, label: String, isConcealed: Bool)] = [
        ("email", "Email", false),
        ("username", "Username", false),
        ("phone", "Phone", false),
        ("title", "Title", false),
        ("firstName", "First name", false),
        ("middleName", "Middle name", false),
        ("lastName", "Last name", false),
        ("company", "Company", false),
        ("address1", "Address 1", false),
        ("address2", "Address 2", false),
        ("address3", "Address 3", false),
        ("city", "City", false),
        ("state", "State", false),
        ("postalCode", "Postal code", false),
        ("country", "Country", false),
        ("ssn", "Social security number", true),
        ("passportNumber", "Passport number", true),
        ("licenseNumber", "License number", true),
    ]

    private static func makeIdentityFields(
        _ identity: [String: String?],
        builder: FieldBuilder
    ) throws -> [VaultField] {
        try identityProperties.compactMap { property in
            try builder.makeField(
                id: "identity.\(property.propertyName)",
                label: property.label,
                isConcealed: property.isConcealed,
                identity[property.propertyName] ?? nil
            )
        }
    }

    private static func makeSshKeyFields(_ sshKey: EncryptedSshKey?, builder: FieldBuilder) throws -> [VaultField] {
        guard let sshKey else {
            return []
        }
        return try [
            builder.makeField(id: "sshKey.publicKey", label: "Public key", sshKey.publicKey),
            builder.makeField(id: "sshKey.keyFingerprint", label: "Fingerprint", sshKey.keyFingerprint),
            builder.makeField(id: "sshKey.privateKey", label: "Private key", isConcealed: true, sshKey.privateKey),
        ].compactMap { $0 }
    }

    private static let hiddenCustomFieldType = 1

    private static func makeCustomFields(
        _ customFields: [EncryptedCustomField],
        builder: FieldBuilder
    ) throws -> [VaultField] {
        try customFields.enumerated().compactMap { fieldIndex, customField in
            let fieldName = try builder.decryptText(customField.name) ?? ""
            // Linked fields have no value of their own and are skipped by `makeField`.
            return try builder.makeField(
                id: "field.\(fieldIndex)",
                label: fieldName.isEmpty ? "Field \(fieldIndex + 1)" : fieldName,
                isConcealed: customField.type == hiddenCustomFieldType,
                customField.value
            )
        }
    }
}

/// Builds the fields of one item, all encrypted with the same item key.
private struct FieldBuilder {
    let itemKey: SymmetricCryptoKey

    func makeField(
        id: String,
        label: String,
        role: VaultFieldRole = .other,
        isConcealed: Bool = false,
        _ serializedValue: String?
    ) throws -> VaultField? {
        guard let serializedValue else {
            return nil
        }
        return VaultField(
            id: id,
            label: label,
            role: role,
            isConcealed: isConcealed,
            encryptedValue: try EncryptedString(serialized: serializedValue),
            itemKey: itemKey
        )
    }

    func decryptText(_ serializedValue: String?) throws -> String? {
        guard let serializedValue else {
            return nil
        }
        return try SymmetricCipher.decryptString(EncryptedString(serialized: serializedValue), with: itemKey)
    }
}
