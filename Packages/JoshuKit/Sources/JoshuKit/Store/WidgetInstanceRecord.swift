import Foundation

/// Where a panel sits on screen. M1 stores the absolute panel frame; M2
/// upgrades to screen-UUID + visibleFrame fractions so positions survive
/// resolution changes and display swaps.
public struct PanelPlacement: Codable, Hashable, Sendable {
    /// Full panel frame origin (includes the shadow inset). nil until the
    /// panel has been shown once — the shell cascades new panels.
    public var origin: CGPoint?
    /// Full panel frame size (includes the shadow inset on every side).
    public var size: CGSize

    public init(origin: CGPoint? = nil, size: CGSize) {
        self.origin = origin
        self.size = size
    }
}

/// One persisted widget instance. `configJSON` is opaque to the store —
/// only the owning descriptor can decode it.
public struct WidgetInstanceRecord: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var typeID: WidgetTypeID
    public var configJSON: Data
    public var placement: PanelPlacement
    public var zIndex: Int
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        typeID: WidgetTypeID,
        configJSON: Data,
        placement: PanelPlacement,
        zIndex: Int = 0,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.typeID = typeID
        self.configJSON = configJSON
        self.placement = placement
        self.zIndex = zIndex
        self.createdAt = createdAt
    }
}
