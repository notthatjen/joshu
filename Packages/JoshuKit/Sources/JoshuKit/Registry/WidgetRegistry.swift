import Foundation

/// Lookup table of installed widget types, populated at launch from
/// BuiltinWidgets. Records whose typeID isn't registered stay on disk and
/// render as a "missing widget type" placeholder (forward compatibility).
@MainActor
public final class WidgetRegistry {
    private let byID: [WidgetTypeID: AnyWidgetDescriptor]
    public let all: [AnyWidgetDescriptor]

    public init(descriptors: [AnyWidgetDescriptor]) {
        all = descriptors
        byID = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.typeID, $0) })
    }

    public func descriptor(for typeID: WidgetTypeID) -> AnyWidgetDescriptor? {
        byID[typeID]
    }
}
