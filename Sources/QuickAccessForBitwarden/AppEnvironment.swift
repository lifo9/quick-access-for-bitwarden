import AppKit

/// What the app runs against: the Bitwarden desktop app installed on this Mac, or the made-up
/// vault of the demo.
@MainActor
struct AppEnvironment {
    let desktop: any DesktopAccess
    let iconStore: WebsiteIconStore
    /// Where the use counts of items are kept.
    let usageDefaults: UserDefaults

    static func makeInstalled() -> AppEnvironment {
        AppEnvironment(desktop: InstalledDesktopApp(), iconStore: WebsiteIconStore(), usageDefaults: .standard)
    }

    /// The demo keeps its use counts apart, so that trying it does not mix invented items into
    /// the preferences of the real app.
    static func makeDemo() throws -> AppEnvironment {
        AppEnvironment(
            desktop: try DemoDesktop(),
            iconStore: WebsiteIconStore(fetchIconData: DemoIcons.makeIconData),
            usageDefaults: UserDefaults(suiteName: "dev.filo.quick-access-for-bitwarden.demo") ?? .standard
        )
    }
}
