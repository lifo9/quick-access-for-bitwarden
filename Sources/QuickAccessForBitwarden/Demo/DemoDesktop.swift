import AppKit
import QuickAccessCore

/// A made-up vault that stands in for the Bitwarden desktop app, to try and to record the panel
/// without anyone's real data. Nothing here touches Bitwarden: the items are invented, encrypted
/// with a key made up at launch, and unlocked without Touch ID.
@MainActor
final class DemoDesktop: DesktopAccess {
    private struct DemoLogin {
        let name: String
        let username: String
        let website: String
        var isFavorite = false
    }

    private static let userId = "demo-account"
    /// The secret of many authenticator examples; it belongs to no account.
    private static let authenticatorKey = "JBSWY3DPEHPK3PXP"

    /// Invented services on the reserved `.example` domain, so no real brand or account appears.
    private static let logins = [
        DemoLogin(
            name: "Acme Cloud", username: "alex@example.com", website: "https://cloud.acme.example", isFavorite: true),
        DemoLogin(name: "Harbor Bank", username: "alex.morgan", website: "https://harborbank.example/login"),
        DemoLogin(name: "Lumen Energy", username: "customer-1002345", website: "https://lumen.example"),
        DemoLogin(name: "Nimbus Mail", username: "alex@nimbus.example", website: "https://mail.nimbus.example"),
        DemoLogin(name: "Orbit Travel", username: "alex@example.com", website: "https://orbit.example"),
        DemoLogin(name: "Pixel Forge", username: "amorgan", website: "https://pixelforge.example"),
        DemoLogin(name: "Pixel Forge (studio)", username: "alex@studio.example", website: "https://pixelforge.example"),
        DemoLogin(name: "Quill Notes", username: "alex@example.com", website: "https://quill.example"),
    ]

    private let userKey: SymmetricCryptoKey
    private let stateFile: Data

    init() throws {
        userKey = try SymmetricCryptoKey(
            encodedKey: RandomBytes.generate(count: SymmetricCryptoKey.encodedByteCount))
        stateFile = try Self.makeStateFile(userKey: userKey)
    }

    func loadState() throws -> DesktopState {
        try DesktopState(stateFileContents: stateFile)
    }

    func readStateModificationDate() throws -> Date? {
        // The demo vault never changes.
        Date(timeIntervalSince1970: 0)
    }

    func requestUnlock(userId: String) async throws -> BiometricUnlockOutcome {
        .unlocked(userKey)
    }

    /// A state file in the desktop app's format, so the demo runs through the same reading and
    /// decryption as a real vault.
    private static func makeStateFile(userKey: SymmetricCryptoKey) throws -> Data {
        func encrypt(_ text: String) throws -> String {
            try SymmetricCipher.encrypt(
                Data(text.utf8),
                with: userKey,
                initializationVector: RandomBytes.generate(count: SymmetricCipher.initializationVectorByteCount)
            ).serialized
        }

        let loginCiphers: [(id: String, cipher: [String: Any])] = try logins.enumerated().map { loginIndex, login in
            let cipher: [String: Any] = [
                "id": "demo-login-\(loginIndex)",
                "type": 1,
                "name": try encrypt(login.name),
                "favorite": login.isFavorite,
                "login": [
                    "username": try encrypt(login.username),
                    "password": try encrypt("correct-horse-battery-staple-\(loginIndex)"),
                    "totp": try encrypt(authenticatorKey),
                    "uris": [["uri": try encrypt(login.website)]],
                ],
            ]
            return ("demo-login-\(loginIndex)", cipher)
        }
        let secureNote: [String: Any] = [
            "id": "demo-note",
            "type": 2,
            "name": try encrypt("Home Wi-Fi"),
            "notes": try encrypt("Network: Lighthouse\nPassword: lanterns-at-dusk"),
        ]
        let card: [String: Any] = [
            "id": "demo-card",
            "type": 3,
            "name": try encrypt("Travel card"),
            "card": [
                "brand": try encrypt("Visa"),
                "cardholderName": try encrypt("Alex Morgan"),
                // The card number payment processors publish for testing.
                "number": try encrypt("4111111111111111"),
                "expMonth": try encrypt("12"),
                "expYear": try encrypt("2030"),
                "code": try encrypt("123"),
            ],
        ]
        let ciphersById = Dictionary(
            uniqueKeysWithValues: loginCiphers + [("demo-note", secureNote), ("demo-card", card)])

        let state: [String: Any] = [
            "global_account_activeAccountId": userId,
            // No organization is involved, so the RSA key is never imported; any value will do.
            "user_\(userId)_crypto_accountCryptographicState": ["V1": ["private_key": try encrypt("unused")]],
            "user_\(userId)_ciphers_ciphers": ciphersById,
            "user_\(userId)_vaultTimeoutSettings_vaultTimeout": "never",
            // Names an icon service so that icons show; `DemoIcons` answers in its place.
            "user_\(userId)_environment_environment": [
                "region": "Self-hosted", "urls": ["base": "https://demo.invalid"],
            ],
        ]
        return try JSONSerialization.data(withJSONObject: state)
    }
}

/// Stands in for the icon service in the demo: draws a colored tile with the website's initial
/// instead of asking anyone for an icon.
enum DemoIcons {
    private static let tilePixels = 64
    private static let tileColors: [NSColor] = [
        .systemBlue, .systemTeal, .systemIndigo, .systemOrange, .systemPink, .systemGreen, .systemPurple,
    ]

    @MainActor
    static func makeIconData(for iconUrl: URL) async throws -> Data {
        // The icon's address is <icon service>/<host name>/icon.png; the tile shows the initial
        // of the name before the top-level domain.
        let hostName = iconUrl.deletingLastPathComponent().lastPathComponent
        let siteName = hostName.split(separator: ".").dropLast().last.map(String.init) ?? hostName
        let initial = siteName.first.map { String($0).uppercased() } ?? "?"
        let tileColor = tileColors[siteName.unicodeScalars.reduce(0) { $0 + Int($1.value) } % tileColors.count]

        guard
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: tilePixels, pixelsHigh: tilePixels, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
                bitsPerPixel: 0),
            let drawingContext = NSGraphicsContext(bitmapImageRep: bitmap)
        else {
            throw CocoaError(.coderInvalidValue)
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = drawingContext
        tileColor.setFill()
        NSRect(x: 0, y: 0, width: tilePixels, height: tilePixels).fill()
        let initialText = NSAttributedString(
            string: initial,
            attributes: [.font: NSFont.systemFont(ofSize: 38, weight: .bold), .foregroundColor: NSColor.white]
        )
        let textSize = initialText.size()
        initialText.draw(
            at: NSPoint(x: (CGFloat(tilePixels) - textSize.width) / 2, y: (CGFloat(tilePixels) - textSize.height) / 2))
        NSGraphicsContext.restoreGraphicsState()

        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.coderInvalidValue)
        }
        return pngData
    }
}
