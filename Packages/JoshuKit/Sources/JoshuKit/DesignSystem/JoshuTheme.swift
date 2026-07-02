import Foundation

/// Design tokens shared by every widget surface. Platform-agnostic — no AppKit.
public enum JoshuTheme {
    /// Corner radius of the glass container.
    public static let cornerRadius: CGFloat = 24

    /// Transparent margin around the visible glass, reserved for the
    /// SwiftUI-drawn drop shadow (the NSPanel itself has `hasShadow = false`).
    /// Clicks in this margin must pass through to windows beneath.
    public static let shadowInset: CGFloat = 30

    /// Opacity of the dark tint wash layered over the behind-window blur.
    public static let tintOpacity: Double = 0.25

    /// Rim-light gradient opacities (top → bottom) that sell the glass edge.
    public static let rimTopOpacity: Double = 0.4
    public static let rimBottomOpacity: Double = 0.06
}
