import SwiftUI

@main
struct JoshuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Joshu", systemImage: "sparkles") {
            MenuBarView(environment: appDelegate.environment)
        }
        .menuBarExtraStyle(.menu)
    }
}
