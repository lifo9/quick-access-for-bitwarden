import Foundation

/// Turns the encrypted desktop state into a searchable vault, given the account's user key.
///
/// Key hierarchy: the user key decrypts the account's RSA private key and personal items; the
/// private key unwraps each organization key; an item may carry its own key, wrapped by the user
/// key or by its organization's key.
public enum VaultDecryptor {
    public static func unlock(_ state: DesktopState, userKey: SymmetricCryptoKey) throws -> UnlockedVault {
        let pkcs8PrivateKey = try decryptPrivateKey(state.encryptedPrivateKey, userKey: userKey)
        // The RSA key is imported only to unwrap organization keys. Without it the items of
        // organizations count as undecryptable; the account's own items do not depend on it.
        let privateKey = try? RsaCipher.makePrivateKey(pkcs8DerEncoded: pkcs8PrivateKey)
        let organizationKeysByOrganizationId = state.organizationKeysByOrganizationId
            .compactMapValues { organizationKey in
                privateKey.flatMap { try? unwrapOrganizationKey(organizationKey, privateKey: $0) }
            }

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

    /// - Returns: The account's RSA private key in PKCS#8 form.
    private static func decryptPrivateKey(
        _ encryptedPrivateKey: String,
        userKey: SymmetricCryptoKey
    ) throws -> Data {
        do {
            return try SymmetricCipher.decrypt(
                EncryptedString(serialized: encryptedPrivateKey),
                with: userKey
            )
        } catch CryptoError.authenticationFailed {
            // The private key is the one value every account has, which makes it the check that
            // the key handed over by the desktop app belongs to the account in the state file.
            throw VaultError.userKeyDoesNotMatchAccount
        }
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

        let noteField = try builder.makeField(id: "notes", name: .standard(.notes), role: .note, cipher.notes)
        let fields =
            kindFields + [noteField].compactMap { $0 }
            + (try makeCustomFields(
                cipher.fields ?? [], canViewHiddenValues: cipher.viewPassword ?? true, builder: builder))
        let websites =
            try fields
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
        let secretFields =
            canViewPassword
            ? [
                try builder.makeField(
                    id: "login.password", name: .standard(.password), role: .password, isConcealed: true, login.password
                ),
                try builder.makeField(
                    id: "login.totp", name: .standard(.oneTimeCode), role: .oneTimeCode, isConcealed: true, login.totp),
            ]
            : []
        let websiteFields = try (login.uris ?? []).enumerated().map { uriIndex, loginUri in
            try builder.makeField(id: "login.uri.\(uriIndex)", name: .standard(.website), role: .website, loginUri.uri)
        }
        let usernameField = try builder.makeField(
            id: "login.username", name: .standard(.username), role: .username, login.username)
        return ([usernameField] + secretFields + websiteFields).compactMap { $0 }
    }

    private static func makeCardFields(_ card: EncryptedCard?, builder: FieldBuilder) throws -> [VaultField] {
        guard let card else {
            return []
        }
        return try [
            builder.makeField(
                id: "card.number", name: .standard(.cardNumber), role: .cardNumber, isConcealed: true, card.number),
            builder.makeField(id: "card.code", name: .standard(.cardSecurityCode), isConcealed: true, card.code),
            builder.makeField(id: "card.cardholderName", name: .standard(.cardholderName), card.cardholderName),
            builder.makeField(id: "card.expMonth", name: .standard(.cardExpirationMonth), card.expMonth),
            builder.makeField(id: "card.expYear", name: .standard(.cardExpirationYear), card.expYear),
            builder.makeField(id: "card.brand", name: .standard(.cardBrand), card.brand),
        ].compactMap { $0 }
    }

    private static let identityProperties: [(propertyName: String, name: VaultFieldName, isConcealed: Bool)] = [
        ("email", .standard(.identityEmail), false),
        ("username", .standard(.identityUsername), false),
        ("phone", .standard(.identityPhone), false),
        ("title", .standard(.identityTitle), false),
        ("firstName", .standard(.identityFirstName), false),
        ("middleName", .standard(.identityMiddleName), false),
        ("lastName", .standard(.identityLastName), false),
        ("company", .standard(.identityCompany), false),
        ("address1", .standard(.identityAddress1), false),
        ("address2", .standard(.identityAddress2), false),
        ("address3", .standard(.identityAddress3), false),
        ("city", .standard(.identityCity), false),
        ("state", .standard(.identityState), false),
        ("postalCode", .standard(.identityPostalCode), false),
        ("country", .standard(.identityCountry), false),
        ("ssn", .standard(.identitySocialSecurityNumber), true),
        ("passportNumber", .standard(.identityPassportNumber), true),
        ("licenseNumber", .standard(.identityLicenseNumber), true),
    ]

    private static func makeIdentityFields(
        _ identity: [String: String?],
        builder: FieldBuilder
    ) throws -> [VaultField] {
        try identityProperties.compactMap { property in
            try builder.makeField(
                id: "identity.\(property.propertyName)",
                name: property.name,
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
            builder.makeField(id: "sshKey.publicKey", name: .standard(.sshPublicKey), sshKey.publicKey),
            builder.makeField(id: "sshKey.keyFingerprint", name: .standard(.sshKeyFingerprint), sshKey.keyFingerprint),
            builder.makeField(
                id: "sshKey.privateKey", name: .standard(.sshPrivateKey), isConcealed: true, sshKey.privateKey),
        ].compactMap { $0 }
    }

    private static let hiddenCustomFieldType = 1

    /// - Parameter canViewHiddenValues: The "view password" permission, which the desktop app
    ///   applies to hidden custom fields as well as to the password.
    private static func makeCustomFields(
        _ customFields: [EncryptedCustomField],
        canViewHiddenValues: Bool,
        builder: FieldBuilder
    ) throws -> [VaultField] {
        try customFields.enumerated().compactMap { fieldIndex, customField in
            let isHidden = customField.type == hiddenCustomFieldType
            guard canViewHiddenValues || !isHidden else {
                return nil
            }
            let fieldName = try builder.decryptText(customField.name) ?? ""
            // Linked fields have no value of their own and are skipped by `makeField`.
            return try builder.makeField(
                id: "field.\(fieldIndex)",
                name: fieldName.isEmpty ? .unnamedCustom(fieldIndex + 1) : .custom(fieldName),
                isConcealed: isHidden,
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
        name: VaultFieldName,
        role: VaultFieldRole = .other,
        isConcealed: Bool = false,
        _ serializedValue: String?
    ) throws -> VaultField? {
        guard let serializedValue else {
            return nil
        }
        return VaultField(
            id: id,
            name: name,
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
