import AppKit
import SwiftUI
import JoshuKit

/// Reconciles the store's records against live panels: creates controllers
/// for new records, closes controllers whose records are gone.
@MainActor
final class PanelManager {
    private var controllers: [UUID: PanelController] = [:]
    private var allVisible = true

    func reconcile(
        records: [WidgetInstanceRecord],
        registry: WidgetRegistry,
        makeShell: (UUID) -> any WidgetShellContext,
        onPlacementChanged: @escaping (UUID, PanelPlacement) -> Void
    ) {
        let liveIDs = Set(records.map(\.id))

        for (id, controller) in controllers where !liveIDs.contains(id) {
            controller.close()
            controllers[id] = nil
        }

        for record in records where controllers[record.id] == nil {
            let content: AnyView
            let service: (any WidgetService)?
            if let descriptor = registry.descriptor(for: record.typeID) {
                let shell = makeShell(record.id)
                content = descriptor.makeView(
                    instanceID: record.id, configJSON: record.configJSON, shell: shell)
                service = descriptor.makeService(
                    instanceID: record.id, configJSON: record.configJSON, shell: shell)
            } else {
                // Unknown type (record from a newer build): keep it on disk,
                // render a placeholder.
                content = AnyView(MissingWidgetView(typeID: record.typeID))
                service = nil
            }

            let controller = PanelController(
                record: record,
                content: content,
                service: service,
                cascadeIndex: controllers.count,
                otherFrames: { [weak self] excluded in
                    guard let self else { return [] }
                    return self.controllers.compactMap { id, controller in
                        id == excluded ? nil : controller.frame
                    }
                },
                onPlacementChanged: onPlacementChanged
            )
            controllers[record.id] = controller
            if allVisible { controller.show() }
        }
    }

    func setAllVisible(_ visible: Bool) {
        allVisible = visible
        for controller in controllers.values {
            visible ? controller.show() : controller.hide()
        }
    }

    /// Display topology changed (unplug, resolution switch): pull every panel
    /// back into a visible screen.
    func reclampAll() {
        for controller in controllers.values {
            controller.reclampToVisibleScreen()
        }
    }
}

/// Placeholder for records whose widget type isn't in this build's registry.
struct MissingWidgetView: View {
    let typeID: WidgetTypeID

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "questionmark.square.dashed")
                .font(.title)
            Text("Unknown widget")
                .font(.headline)
            Text(typeID.rawValue)
                .font(.caption.monospaced())
                .opacity(0.6)
        }
        .foregroundStyle(.white.opacity(0.8))
        .padding(20)
    }
}
