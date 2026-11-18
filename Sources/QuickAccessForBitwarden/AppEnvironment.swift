import AppKit

/// What the app runs against: the Bitwarden desktop app installed on this Mac, or the made-up
/// vault of the demo.
@MainActor
struct AppEnvironment {
    let desktop: any DesktopAccess
    let iconStore: WebsiteIconStore
    /// Where the use counts of items are kept.
    let usageDefaults: UserDefaults
    /// Whether hiding the menu bar icon lasts beyond this run.
    let remembersMenuBarIcon: Bool

    static func makeInstalled() -> AppEnvironment {
        AppEnvironment(
            desktop: InstalledDesktopApp(),
            iconStore: WebsiteIconStore(),
            usageDefaults: .standard,
            remembersMenuBarIcon: true
        )
    }

    /// The demo keeps its use counts apart and does not remember a hidden menu bar icon, so that
    /// trying it leaves no trace in the preferences of the real app.
    static func makeDemo() throws -> AppEnvironment {
        AppEnvironment(
            desktop: try DemoDesktop(),
            iconStore: WebsiteIconStore(fetchIconData: DemoIcons.makeIconData),
            usageDefaults: UserDefaults(suiteName: "dev.filo.quick-access-for-bitwarden.demo") ?? .standard,
            remembersMenuBarIcon: false
        )
    }
}
