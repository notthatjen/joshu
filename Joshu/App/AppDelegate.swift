import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let environment = AppEnvironment()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // LSUIElement is set in Info.plist; set the policy defensively too.
        NSApp.setActivationPolicy(.accessory)
        MainMenuBuilder.installHiddenEditMenu()
        environment.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Flush any debounced store writes.
        environment.willTerminate()
    }
}
