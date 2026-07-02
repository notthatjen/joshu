import AppKit

/// Content-view container that ignores clicks in the transparent shadow
/// margin so they reach whatever window is beneath the panel. The panel frame
/// is `shadowInset` larger than the visible glass on every side.
final class PassThroughMarginView: NSView {
    var margin: CGFloat = 0

    override func hitTest(_ point: NSPoint) -> NSView? {
        // `point` is in the superview's coordinate system.
        let local = convert(point, from: superview)
        guard bounds.insetBy(dx: margin, dy: margin).contains(local) else { return nil }
        return super.hitTest(point)
    }
}
