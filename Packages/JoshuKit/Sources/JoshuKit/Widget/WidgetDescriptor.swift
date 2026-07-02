import SwiftUI

/// Stable identity of a widget *type* (not an instance), e.g. "com.wren.joshu.notes".
public struct WidgetTypeID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Gallery-facing description of a widget type.
public struct WidgetMetadata: Sendable {
    public let displayName: String
    public let systemImage: String
    public let summary: String
    /// Size of the visible glass (the shell adds the shadow inset around it).
    public let defaultSize: CGSize
    public let allowsMultipleInstances: Bool

    public init(
        displayName: String,
        systemImage: String,
        summary: String,
        defaultSize: CGSize,
        allowsMultipleInstances: Bool = true
    ) {
        self.displayName = displayName
        self.systemImage = systemImage
        self.summary = summary
        self.defaultSize = defaultSize
        self.allowsMultipleInstances = allowsMultipleInstances
    }
}

/// Per-instance configuration. `init()` provides the defaults a fresh
/// instance gets from the gallery "+" flow.
public protocol WidgetConfig: Codable, Hashable, Sendable {
    init()
}

/// Optional background work a widget keeps running even while hidden
/// (e.g. meeting-transcript polling). Stopped only on instance removal/quit.
public protocol WidgetService: AnyObject {
    func start() async
    func stop() async
}

/// A widget type: metadata + view factory + optional background service.
/// Implementations are stateless namespaces (enums); all per-instance state
/// lives in the WidgetModel/config.
@MainActor
public protocol WidgetDescriptor {
    associatedtype Config: WidgetConfig
    associatedtype Content: View

    static var typeID: WidgetTypeID { get }
    static var metadata: WidgetMetadata { get }

    @ViewBuilder
    static func makeView(model: WidgetModel<Config>) -> Content
    static func makeService(model: WidgetModel<Config>) -> (any WidgetService)?
}

extension WidgetDescriptor {
    public static func makeService(model: WidgetModel<Config>) -> (any WidgetService)? { nil }
}
