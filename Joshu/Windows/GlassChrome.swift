import AppKit
import SwiftUI
import JoshuKit

/// Behind-window blur. SwiftUI materials blend within-window and look flat on
/// a transparent panel; NSVisualEffectView with .behindWindow samples the
/// screen content beneath. Corner rounding must go through maskImage —
/// layer.cornerRadius/clipShape do not reliably clip behind-window blur.
struct BehindWindowBlur: NSViewRepresentable {
    var cornerRadius: CGFloat = JoshuTheme.cornerRadius

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .hudWindow
        view.state = .active // stay blurred while the app is inactive (it always is)
        view.maskImage = .roundedRectMask(radius: cornerRadius)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.maskImage = .roundedRectMask(radius: cornerRadius)
    }
}

/// Liquid Glass backdrop on macOS 26+, NSVisualEffectView blur before that,
/// and a solid fill when Reduce Transparency is on.
struct GlassBackdrop: View {
    var cornerRadius: CGFloat = JoshuTheme.cornerRadius
    @State private var reduceTransparency =
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        Group {
            if reduceTransparency {
                shape.fill(Color(nsColor: .windowBackgroundColor))
            } else if #available(macOS 26.0, *) {
                shape
                    .fill(.clear)
                    .glassEffect(.regular.tint(.black.opacity(JoshuTheme.tintOpacity)), in: shape)
            } else {
                ZStack {
                    BehindWindowBlur(cornerRadius: cornerRadius)
                    shape.fill(.black.opacity(JoshuTheme.tintOpacity))
                }
            }
        }
        .onReceive(
            NSWorkspace.shared.notificationCenter.publisher(
                for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
        ) { _ in
            reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        }
    }
}

extension NSImage {
    /// Resizable rounded-rect mask with cap insets so corners stay crisp at
    /// any view size.
    static func roundedRectMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// Fills its area and turns any mouse-down into a native window drag, so the
/// whole glass surface moves the panel while controls layered above still win
/// hit-testing.
struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }

    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// The glass container every widget renders inside: backdrop, rim light,
/// drop shadow inside the transparent shadow inset, and hover chrome
/// (close button) when the shell provides `onClose`.
struct WidgetChrome<Content: View>: View {
    var onClose: (() -> Void)?
    @ViewBuilder var content: () -> Content

    @State private var hovering = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: JoshuTheme.cornerRadius, style: .continuous)
    }

    var body: some View {
        ZStack {
            GlassBackdrop()
            WindowDragArea()
            content()
        }
        .overlay(
            shape.strokeBorder(
                LinearGradient(
                    colors: [
                        .white.opacity(JoshuTheme.rimTopOpacity),
                        .white.opacity(JoshuTheme.rimBottomOpacity),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1
            )
        )
        .overlay(alignment: .topLeading) {
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 18, height: 18)
                        .background(.black.opacity(0.45), in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .padding(8)
                .opacity(hovering ? 1 : 0)
                .animation(.easeOut(duration: 0.15), value: hovering)
            }
        }
        .onHover { hovering = $0 }
        .compositingGroup()
        .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
        .padding(JoshuTheme.shadowInset)
    }
}
