import AppKit

let launchArguments = Set(CommandLine.arguments.dropFirst())

if launchArguments.contains("--diagnose") {
    let includingUnlock = launchArguments.contains("--unlock")
    Task {
        exit(await Diagnostics.run(includingUnlock: includingUnlock))
    }
    // Runs the task above; the process ends through its `exit`.
    dispatchMain()
}

let application = NSApplication.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
// A menu bar app: no Dock icon and no main menu.
application.setActivationPolicy(.accessory)
application.run()
