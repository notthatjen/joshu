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

/// The glass container every widget renders inside: behind-window blur, dark
/// tint, rim light, and a SwiftUI drop shadow drawn inside the transparent
/// shadow inset.
struct WidgetChrome<Content: View>: View {
    @ViewBuilder var content: () -> Content

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: JoshuTheme.cornerRadius, style: .continuous)
    }

    var body: some View {
        ZStack {
            BehindWindowBlur()
            shape.fill(.black.opacity(JoshuTheme.tintOpacity))
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
        .compositingGroup()
        .shadow(color: .black.opacity(0.35), radius: 24, y: 10)
        .padding(JoshuTheme.shadowInset)
    }
}
