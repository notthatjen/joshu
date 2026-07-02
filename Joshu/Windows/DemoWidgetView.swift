import SwiftUI

/// M0 placeholder widget: proves glass rendering, dragging, and text input in
/// a nonactivating panel. Replaced by real widgets from M1 on.
struct DemoWidgetView: View {
    @State private var scratch = ""

    var body: some View {
        WidgetChrome {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.white.opacity(0.9))
                    Text("Joshu")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.9))
                    Spacer()
                }

                Text("Floating glass shell is alive. Drag me anywhere; ⌥Space hides me.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()

                TextField("Type here without activating the app…", text: $scratch)
                    .textFieldStyle(.roundedBorder)
            }
            .padding(20)
        }
    }
}
