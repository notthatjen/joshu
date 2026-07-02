import SwiftUI
import JoshuKit

struct MenuBarView: View {
    let environment: AppEnvironment

    var body: some View {
        Button(environment.panelsVisible ? "Hide Widgets" : "Show Widgets") {
            environment.toggleVisibility()
        }
        .keyboardShortcut(.space, modifiers: .option)

        Button("Add Widget…") {
            environment.showGallery()
        }

        if !environment.store.records.isEmpty {
            Divider()
            Menu("Remove Widget") {
                ForEach(environment.store.records) { record in
                    Button(environment.displayName(for: record)) {
                        environment.removeWidget(id: record.id)
                    }
                }
            }
        }

        Divider()

        Button("Quit Joshu") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
