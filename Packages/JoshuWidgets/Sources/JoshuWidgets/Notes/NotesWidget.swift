import SwiftUI
import JoshuKit

public struct NotesConfig: WidgetConfig {
    public var text: String = ""
    public init() {}
}

/// M1 proving-ground widget: editable text persisted through the config
/// pipeline (model → shell → store → disk). Also doubles as a handy scratchpad.
public enum NotesWidget: WidgetDescriptor {
    public static let typeID = WidgetTypeID(rawValue: "com.wren.joshu.notes")

    public static let metadata = WidgetMetadata(
        displayName: "Notes",
        systemImage: "note.text",
        summary: "A floating glass scratchpad. Text persists across relaunches.",
        defaultSize: CGSize(width: 320, height: 260)
    )

    public static func makeView(model: WidgetModel<NotesConfig>) -> some View {
        NotesView(model: model)
    }
}

private struct NotesView: View {
    @Bindable var model: WidgetModel<NotesConfig>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "note.text")
                Text("Notes")
                    .font(.headline)
                Spacer()
            }
            .foregroundStyle(.white.opacity(0.9))

            TextEditor(text: $model.config.text)
                .font(.body)
                .foregroundStyle(.white.opacity(0.9))
                .scrollContentBackground(.hidden)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .padding(16)
    }
}
