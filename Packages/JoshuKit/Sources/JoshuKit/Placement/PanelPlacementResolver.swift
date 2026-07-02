import Foundation

/// Platform-agnostic description of one display, keyed by a stable UUID so
/// placements survive display reconnects and resolution changes.
public struct ScreenInfo: Hashable, Sendable {
    public let uuid: String?
    public let visibleFrame: CGRect

    public init(uuid: String?, visibleFrame: CGRect) {
        self.uuid = uuid
        self.visibleFrame = visibleFrame
    }
}

/// Pure placement ↔ frame conversion with off-screen clamping.
public enum PanelPlacementResolver {
    /// Resolve a stored placement to a concrete frame. Preference order:
    /// fraction on its remembered screen → fraction on the main screen →
    /// legacy absolute origin → nil (caller cascades).
    /// The result is always clamped into the chosen screen's visibleFrame.
    public static func frame(
        for placement: PanelPlacement,
        screens: [ScreenInfo],
        mainScreen: ScreenInfo?
    ) -> CGRect? {
        let size = placement.size

        if let fraction = placement.originFraction {
            let screen = screens.first { $0.uuid != nil && $0.uuid == placement.screenUUID }
                ?? mainScreen
                ?? screens.first
            guard let screen else { return nil }
            let vf = screen.visibleFrame
            let origin = CGPoint(
                x: vf.minX + fraction.x * vf.width,
                y: vf.minY + fraction.y * vf.height
            )
            return clamp(CGRect(origin: origin, size: size), into: vf)
        }

        if let origin = placement.origin {
            let frame = CGRect(origin: origin, size: size)
            let screen = screens.max(by: {
                $0.visibleFrame.intersection(frame).area < $1.visibleFrame.intersection(frame).area
            }) ?? mainScreen
            guard let screen else { return frame }
            return clamp(frame, into: screen.visibleFrame)
        }

        return nil
    }

    /// Compute the placement to persist for a live frame: remember the screen
    /// holding the frame's center and the origin as visibleFrame fractions.
    public static func placement(for frame: CGRect, screens: [ScreenInfo]) -> PanelPlacement {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let screen = screens.first { $0.visibleFrame.contains(center) }
            ?? screens.max(by: {
                $0.visibleFrame.intersection(frame).area < $1.visibleFrame.intersection(frame).area
            })

        guard let screen, screen.visibleFrame.width > 0, screen.visibleFrame.height > 0 else {
            return PanelPlacement(origin: frame.origin, size: frame.size)
        }

        let vf = screen.visibleFrame
        return PanelPlacement(
            origin: frame.origin,
            size: frame.size,
            screenUUID: screen.uuid,
            originFraction: CGPoint(
                x: (frame.minX - vf.minX) / vf.width,
                y: (frame.minY - vf.minY) / vf.height
            )
        )
    }

    /// Shift a frame so it sits inside `container` (top-left priority when it
    /// doesn't fit — origin is never pushed below the container's origin).
    public static func clamp(_ frame: CGRect, into container: CGRect) -> CGRect {
        var result = frame
        if result.maxX > container.maxX { result.origin.x = container.maxX - result.width }
        if result.minX < container.minX { result.origin.x = container.minX }
        if result.maxY > container.maxY { result.origin.y = container.maxY - result.height }
        if result.minY < container.minY { result.origin.y = container.minY }
        return result
    }
}

private extension CGRect {
    var area: CGFloat { isNull || isEmpty ? 0 : width * height }
}
