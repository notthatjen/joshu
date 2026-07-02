import SwiftUI
import KeyboardShortcuts

struct MenuBarView: View {
    let environment: AppEnvironment

    var body: some View {
        Button(environment.panelsVisible ? "Hide Widgets" : "Show Widgets") {
            environment.toggleVisibility()
        }
        .keyboardShortcut(.space, modifiers: .option)

        Divider()

        Button("Quit Joshu") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
