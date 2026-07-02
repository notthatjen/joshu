import SwiftUI
import JoshuKit

public struct ChatHeadsConfig: WidgetConfig {
    public init() {}
}

/// M3 proving-ground widget for the auxiliary-window API: a stack of circular
/// avatars; tapping one opens an anchored floating chat window. The coding
/// widget (M6) replaces the fake threads with real Claude/Codex sessions.
public enum ChatHeadsWidget: WidgetDescriptor {
    public static let typeID = WidgetTypeID(rawValue: "com.wren.joshu.chatheads-demo")

    public static let metadata = WidgetMetadata(
        displayName: "Chat Heads (demo)",
        systemImage: "bubble.left.and.bubble.right",
        summary: "Floating avatars that open anchored chat windows. API demo for the coding widget.",
        defaultSize: CGSize(width: 88, height: 240)
    )

    public static func makeView(model: WidgetModel<ChatHeadsConfig>) -> some View {
        ChatHeadsView(model: model)
    }
}

private struct DemoThread: Identifiable {
    let id: String
    let name: String
    let initials: String
    let hue: Double
}

private let demoThreads: [DemoThread] = [
    DemoThread(id: "alpha", name: "Session Alpha", initials: "SA", hue: 0.58),
    DemoThread(id: "beta", name: "Session Beta", initials: "SB", hue: 0.08),
    DemoThread(id: "gamma", name: "Session Gamma", initials: "SG", hue: 0.32),
]

private struct ChatHeadsView: View {
    let model: WidgetModel<ChatHeadsConfig>

    var body: some View {
        VStack(spacing: 12) {
            ForEach(demoThreads) { thread in
                Button {
                    model.shell.presentAuxiliaryWindow(
                        key: thread.id,
                        options: AuxiliaryWindowOptions(
                            size: CGSize(width: 300, height: 360),
                            attachment: .anchored(edge: .trailing, gap: 12)
                        )
                    ) {
                        DemoChatView(thread: thread)
                    }
                } label: {
                    Circle()
                        .fill(Color(hue: thread.hue, saturation: 0.55, brightness: 0.85).gradient)
                        .frame(width: 48, height: 48)
                        .overlay(
                            Text(thread.initials)
                                .font(.subheadline.bold())
                                .foregroundStyle(.white)
                        )
                        .overlay(Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
    }
}

private struct DemoChatView: View {
    let thread: DemoThread
    @State private var draft = ""
    @State private var messages: [String]

    init(thread: DemoThread) {
        self.thread = thread
        _messages = State(initialValue: ["Hi! This is \(thread.name).", "Aux windows work."])
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(thread.name)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.9))

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                        Text(message)
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            TextField("Message…", text: $draft)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    guard !draft.isEmpty else { return }
                    messages.append(draft)
                    draft = ""
                }
        }
        .padding(16)
    }
}
