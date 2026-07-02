import SwiftUI
import Observation
import Combine

public struct ActionToast: Identifiable, Sendable {
    public let id = UUID()
    public let item: ActionItem
    public let meetingTitle: String
    public let defaultWorkspace: String
}

/// App-global queue of immediate action-item toasts. The app shell observes
/// this and renders each as an auto-hiding edge popup; widgets just enqueue.
@MainActor
@Observable
public final class ToastCenter {
    public static let shared = ToastCenter()
    public private(set) var toasts: [ActionToast] = []

    private init() {}

    public func present(_ toast: ActionToast) {
        toasts.append(toast)
    }

    public func dismiss(_ id: UUID) {
        toasts.removeAll { $0.id == id }
    }
}

/// The toast body (no glass chrome — the shell wraps it). Copy prompt to the
/// pasteboard, or Run with Claude which spawns a session in a workspace.
public struct ActionToastView: View {
    public let toast: ActionToast
    public var onRunWithClaude: (String, String) -> Void  // (workspace, prompt)
    public var onDismiss: () -> Void

    @State private var secondsLeft = 12
    @State private var copied = false

    private var timer: some Publisher<Date, Never> {
        Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    }

    public init(
        toast: ActionToast,
        onRunWithClaude: @escaping (String, String) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.toast = toast
        self.onRunWithClaude = onRunWithClaude
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(toast.meetingTitle, systemImage: "bolt.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.yellow.opacity(0.9))
                    .lineLimit(1)
                Spacer()
                Text("\(secondsLeft)s")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.4))
                Button(action: onDismiss) {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.5))
            }

            Text(toast.item.text)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button {
                    let text = toast.item.suggestedPrompt ?? toast.item.text
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy prompt", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    let prompt = toast.item.suggestedPrompt ?? toast.item.text
                    onRunWithClaude(toast.defaultWorkspace, prompt)
                } label: {
                    Label("Run with Claude", systemImage: "sparkle")
                        .font(.caption)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 300, alignment: .leading)
        .onReceive(timer) { _ in
            secondsLeft -= 1
            if secondsLeft <= 0 { onDismiss() }
        }
        .onHover { hovering in
            if hovering { secondsLeft = max(secondsLeft, 8) } // pause-ish on hover
        }
    }
}
