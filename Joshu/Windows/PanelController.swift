import AppKit
import SwiftUI
import JoshuKit

/// Owns one FloatingPanel hosting one widget instance. Resolves the stored
/// placement to a frame, snaps after drags, reports placement changes back to
/// the store, and runs the widget's optional background service.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    let instanceID: UUID

    private let panel: FloatingPanel
    private let onPlacementChanged: (UUID, PanelPlacement) -> Void
    private let otherFrames: (UUID) -> [NSRect]
    private var service: (any WidgetService)?
    private var serviceTask: Task<Void, Never>?
    private var snapTask: Task<Void, Never>?

    init(
        record: WidgetInstanceRecord,
        content: AnyView,
        service: (any WidgetService)?,
        cascadeIndex: Int,
        otherFrames: @escaping (UUID) -> [NSRect],
        onPlacementChanged: @escaping (UUID, PanelPlacement) -> Void
    ) {
        instanceID = record.id
        self.service = service
        self.otherFrames = otherFrames
        self.onPlacementChanged = onPlacementChanged

        let frame = PanelPlacementResolver.frame(
            for: record.placement,
            screens: NSScreen.allScreenInfos,
            mainScreen: NSScreen.main?.screenInfo
        ) ?? Self.cascadeFrame(size: record.placement.size, index: cascadeIndex)

        panel = FloatingPanel(contentRect: frame)
        super.init()
        panel.delegate = self

        let container = PassThroughMarginView()
        container.margin = JoshuTheme.shadowInset

        let host = NSHostingView(rootView: WidgetChrome { content })
        // Default sizingOptions let SwiftUI's intrinsic size drive the window
        // frame; the stored placement is the boss.
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
        panel.setFrame(frame, display: false)

        if record.placement.originFraction == nil {
            // Fresh cascade or legacy record: persist the resolved spot.
            persistPlacement()
        }

        if let service {
            serviceTask = Task { await service.start() }
        }
    }

    private static func cascadeFrame(size: CGSize, index: Int) -> NSRect {
        let screen = NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let offset = CGFloat(index % 8) * 28
        let origin = NSPoint(
            x: screen.midX - size.width / 2 + offset,
            y: screen.midY - size.height / 2 - offset
        )
        return PanelPlacementResolver.clamp(NSRect(origin: origin, size: size), into: screen)
    }

    // MARK: - Visibility & teardown

    func show() { panel.orderFrontRegardless() }
    func hide() { panel.orderOut(nil) }

    func close() {
        let service = service
        self.service = nil
        serviceTask?.cancel()
        snapTask?.cancel()
        Task { await service?.stop() }
        panel.delegate = nil
        panel.close()
    }

    /// Pull the panel back inside a visible screen (display unplug/resize).
    func reclampToVisibleScreen() {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let clamped = PanelPlacementResolver.clamp(panel.frame, into: screen.visibleFrame)
        guard clamped != panel.frame else { return }
        panel.setFrame(clamped, display: true)
        persistPlacement()
    }

    // MARK: - Placement persistence & snapping

    private func persistPlacement() {
        let placement = PanelPlacementResolver.placement(
            for: panel.frame, screens: NSScreen.allScreenInfos)
        onPlacementChanged(instanceID, placement)
    }

    private func scheduleSnap() {
        snapTask?.cancel()
        snapTask = Task { [weak self] in
            // Debounce: windowDidMove streams during a drag; snap when it stops.
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            self?.snapNow()
        }
    }

    private func snapNow() {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let snapped = SnapEngine.snappedFrame(
            proposed: panel.frame,
            others: otherFrames(instanceID),
            screen: screen.visibleFrame,
            inset: JoshuTheme.shadowInset
        )
        guard snapped != panel.frame else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().setFrame(snapped, display: true)
        }
        // windowDidMove fires again from the animation; placement persists there.
    }

    var frame: NSRect { panel.frame }

    // MARK: - NSWindowDelegate

    func windowDidMove(_ notification: Notification) {
        persistPlacement()
        scheduleSnap()
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        persistPlacement()
    }
}
