import AppKit
import Observation
import JoshuKit
import JoshuWidgets

/// Composition root. Owns the store, registry, panel layer, and global
/// services; mediates every widget mutation.
@MainActor
@Observable
final class AppEnvironment {
    let registry: WidgetRegistry
    let store: WidgetStore
    private(set) var panelsVisible = true

    @ObservationIgnored private let panelManager = PanelManager()
    @ObservationIgnored private let gallery = GalleryWindowController()
    @ObservationIgnored private var hotkey: HotkeyManager?

    init() {
        registry = WidgetRegistry(descriptors: BuiltinWidgets.all)
        store = WidgetStore(fileURL: WidgetStore.defaultFileURL())
    }

    func start() {
        // First launch nicety: an empty overlay is indistinguishable from a
        // broken one — seed a Notes widget.
        if store.records.isEmpty, let first = registry.all.first {
            addWidget(first.typeID)
        } else {
            reconcile()
        }

        let hotkey = HotkeyManager()
        hotkey.onToggle = { [weak self] in self?.toggleVisibility() }
        self.hotkey = hotkey

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.panelManager.reclampAll()
            }
        }
    }

    func willTerminate() {
        store.saveNow()
    }

    // MARK: - Widget mutations

    func addWidget(_ typeID: WidgetTypeID) {
        guard let descriptor = registry.descriptor(for: typeID) else { return }
        let glass = descriptor.metadata.defaultSize
        let inset = JoshuTheme.shadowInset
        let record = WidgetInstanceRecord(
            typeID: typeID,
            configJSON: descriptor.defaultConfigJSON(),
            placement: PanelPlacement(
                size: CGSize(width: glass.width + inset * 2, height: glass.height + inset * 2))
        )
        store.add(record)
        reconcile()
    }

    func removeWidget(id: UUID) {
        store.remove(id: id)
        reconcile()
    }

    func displayName(for record: WidgetInstanceRecord) -> String {
        registry.descriptor(for: record.typeID)?.metadata.displayName ?? record.typeID.rawValue
    }

    // MARK: - UI actions

    func showGallery() {
        gallery.show(registry: registry) { [weak self] typeID in
            self?.addWidget(typeID)
        }
    }

    func toggleVisibility() {
        panelsVisible.toggle()
        panelManager.setAllVisible(panelsVisible)
    }

    // MARK: - Reconciliation

    private func reconcile() {
        panelManager.reconcile(
            records: store.records,
            registry: registry,
            makeShell: { [weak self] _ in
                MacWidgetShellContext(
                    onConfigChange: { [weak self] id, json in
                        self?.store.updateConfig(id: id, configJSON: json)
                    },
                    onRemove: { [weak self] id in
                        self?.removeWidget(id: id)
                    }
                )
            },
            onPlacementChanged: { [weak self] id, placement in
                self?.store.updatePlacement(id: id, placement: placement)
            }
        )
    }
}
