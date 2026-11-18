import AppKit

let launchArguments = Array(CommandLine.arguments.dropFirst())

if launchArguments.contains("--diagnose") {
    let includingUnlock = launchArguments.contains("--unlock")
    Task {
        exit(await Diagnostics.run(includingUnlock: includingUnlock))
    }
    // Runs the task above; the process ends through its `exit`.
    dispatchMain()
}

let application = NSApplication.shared

// `--record-demo <path prefix>` writes the screencast of the README and exits. It is run from the
// repository's root, where it finds the app's icon.
if let flagIndex = launchArguments.firstIndex(of: "--record-demo") {
    guard launchArguments.indices.contains(flagIndex + 1) else {
        print("usage: --record-demo <output path prefix>")
        exit(2)
    }
    let outputPathPrefix = launchArguments[flagIndex + 1]
    Task {
        do {
            try await DemoRecorder.record(outputPathPrefix: outputPathPrefix)
            exit(0)
        } catch {
            print("recording failed: \(error)")
            exit(1)
        }
    }
    // Drawing the views needs the app's run loop, though nothing comes on screen.
    application.setActivationPolicy(.prohibited)
    application.run()
}

// `--demo` runs the app against an invented vault instead of the Bitwarden desktop app.
let appDelegate = AppDelegate(
    environment: launchArguments.contains("--demo") ? try AppEnvironment.makeDemo() : .makeInstalled()
)
application.delegate = appDelegate
// A menu bar app: no Dock icon and no main menu.
application.setActivationPolicy(.accessory)
application.run()
