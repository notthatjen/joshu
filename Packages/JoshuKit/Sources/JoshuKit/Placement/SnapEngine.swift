import Foundation

/// Pure snapping math: pulls a dragged panel's *visible glass* edges onto
/// screen edges and other panels' glass edges when within `threshold`.
/// All rects are full panel frames; `inset` is the transparent shadow margin
/// between panel frame and visible glass.
public enum SnapEngine {
    public static func snappedFrame(
        proposed: CGRect,
        others: [CGRect],
        screen: CGRect,
        threshold: CGFloat = 12,
        inset: CGFloat = 0
    ) -> CGRect {
        let glass = proposed.insetBy(dx: inset, dy: inset)

        var xTargets: [CGFloat] = [screen.minX, screen.maxX]
        var yTargets: [CGFloat] = [screen.minY, screen.maxY]
        for other in others {
            let otherGlass = other.insetBy(dx: inset, dy: inset)
            xTargets += [otherGlass.minX, otherGlass.maxX]
            yTargets += [otherGlass.minY, otherGlass.maxY]
        }

        let dx = bestDelta(edges: [glass.minX, glass.maxX], targets: xTargets, threshold: threshold)
        let dy = bestDelta(edges: [glass.minY, glass.maxY], targets: yTargets, threshold: threshold)

        return proposed.offsetBy(dx: dx, dy: dy)
    }

    /// Smallest edge→target correction within threshold, or 0.
    private static func bestDelta(edges: [CGFloat], targets: [CGFloat], threshold: CGFloat) -> CGFloat {
        var best: CGFloat = 0
        var bestMagnitude = threshold.nextUp
        for edge in edges {
            for target in targets {
                let delta = target - edge
                if abs(delta) <= threshold, abs(delta) < bestMagnitude {
                    best = delta
                    bestMagnitude = abs(delta)
                }
            }
        }
        return best
    }
}
