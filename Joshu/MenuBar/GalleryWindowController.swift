import AppKit
import SwiftUI
import JoshuKit

/// The "+" flow: a small activating window listing widget types from the
/// registry. Activating (unlike widget panels) so Escape/close behave
/// naturally.
@MainActor
final class GalleryWindowController {
    private var window: NSWindow?

    func show(registry: WidgetRegistry, onAdd: @escaping (WidgetTypeID) -> Void) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate()
            return
        }

        let view = GalleryView(descriptors: registry.all) { [weak self] typeID in
            onAdd(typeID)
            self?.dismiss()
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Add Widget"
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.center()
        self.window = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    func dismiss() {
        window?.close()
        window = nil
    }
}

private struct GalleryView: View {
    let descriptors: [AnyWidgetDescriptor]
    let onAdd: (WidgetTypeID) -> Void

    private let columns = [GridItem(.adaptive(minimum: 180), spacing: 12)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(descriptors) { descriptor in
                    Button {
                        onAdd(descriptor.typeID)
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: descriptor.metadata.systemImage)
                                .font(.title)
                            Text(descriptor.metadata.displayName)
                                .font(.headline)
                            Text(descriptor.metadata.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, minHeight: 120)
                        .padding(12)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
    }
}
