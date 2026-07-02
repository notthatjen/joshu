import AppKit
import SwiftUI
import Observation
import JoshuKit
import JoshuWidgets

/// Watches ToastCenter and renders each immediate action item as a glass
/// popup stacked at the top-right screen edge. Auto-hide + Run-with-Claude
/// are handled in ActionToastView; this owns the panels.
@MainActor
final class ToastHostController {
    private var panels: [UUID: FloatingPanel] = [:]
    private var observation: (@Sendable () -> Void)?
    private let onRunWithClaude: (String, String) -> Void

    init(onRunWithClaude: @escaping (String, String) -> Void) {
        self.onRunWithClaude = onRunWithClaude
        observeToasts()
    }

    private func observeToasts() {
        withObservationTracking {
            _ = ToastCenter.shared.toasts
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.sync()
                self?.observeToasts() // re-arm (one-shot tracking)
            }
        }
    }

    private func sync() {
        let toasts = ToastCenter.shared.toasts
        let liveIDs = Set(toasts.map(\.id))

        for (id, panel) in panels where !liveIDs.contains(id) {
            panel.close()
            panels[id] = nil
        }

        for (index, toast) in toasts.enumerated() where panels[toast.id] == nil {
            present(toast, index: index)
        }
        relayout()
    }

    private func present(_ toast: ActionToast, index: Int) {
        let inset = JoshuTheme.shadowInset
        let size = NSSize(width: 300 + inset * 2, height: 150 + inset * 2)
        let panel = FloatingPanel(contentRect: NSRect(origin: .zero, size: size))
        panel.level = .statusBar // above widgets and most system UI

        let view = ActionToastView(
            toast: toast,
            onRunWithClaude: { [weak self] workspace, prompt in
                self?.onRunWithClaude(workspace, prompt)
                ToastCenter.shared.dismiss(toast.id)
            },
            onDismiss: { ToastCenter.shared.dismiss(toast.id) })

        let container = PassThroughMarginView()
        container.margin = inset
        let host = NSHostingView(rootView: WidgetChrome { AnyView(view) })
        host.sizingOptions = []
        host.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.topAnchor.constraint(equalTo: container.topAnchor),
            host.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        panel.contentView = container
        panels[toast.id] = panel
        panel.orderFrontRegardless()
    }

    /// Stack panels down the top-right edge.
    private func relayout() {
        guard let screen = NSScreen.main?.visibleFrame else { return }
        var y = screen.maxY
        for id in panels.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let panel = panels[id] else { continue }
            let frame = panel.frame
            let origin = NSPoint(x: screen.maxX - frame.width + JoshuTheme.shadowInset,
                                 y: y - frame.height + JoshuTheme.shadowInset)
            panel.setFrameOrigin(origin)
            y -= frame.height - JoshuTheme.shadowInset
        }
    }
}
