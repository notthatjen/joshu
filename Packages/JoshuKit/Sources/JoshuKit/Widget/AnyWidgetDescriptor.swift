import SwiftUI

/// Type-erased widget descriptor so the registry can hold heterogeneous
/// widget types. Deliberately a thin box: erased config codec + view factory
/// + service factory, nothing else.
@MainActor
public struct AnyWidgetDescriptor: Identifiable {
    public let typeID: WidgetTypeID
    public let metadata: WidgetMetadata
    public var id: WidgetTypeID { typeID }

    private let makeDefaultConfigJSON: () -> Data
    private let makeViewClosure: (UUID, Data, any WidgetShellContext) -> AnyView
    private let makeServiceClosure: (UUID, Data, any WidgetShellContext) -> (any WidgetService)?

    public init<D: WidgetDescriptor>(_ descriptor: D.Type) {
        typeID = D.typeID
        metadata = D.metadata
        makeDefaultConfigJSON = {
            (try? JSONEncoder().encode(D.Config())) ?? Data("{}".utf8)
        }
        makeViewClosure = { instanceID, configJSON, shell in
            let model = Self.model(D.self, instanceID, configJSON, shell)
            return AnyView(D.makeView(model: model))
        }
        makeServiceClosure = { instanceID, configJSON, shell in
            D.makeService(model: Self.model(D.self, instanceID, configJSON, shell))
        }
    }

    private static func model<D: WidgetDescriptor>(
        _ descriptor: D.Type, _ instanceID: UUID, _ configJSON: Data, _ shell: any WidgetShellContext
    ) -> WidgetModel<D.Config> {
        // Tolerant decode: a config written by a newer/older build falls back
        // to defaults instead of bricking the widget.
        let config = (try? JSONDecoder().decode(D.Config.self, from: configJSON)) ?? D.Config()
        return WidgetModel(instanceID: instanceID, config: config, shell: shell)
    }

    public func defaultConfigJSON() -> Data {
        makeDefaultConfigJSON()
    }

    public func makeView(instanceID: UUID, configJSON: Data, shell: any WidgetShellContext) -> AnyView {
        makeViewClosure(instanceID, configJSON, shell)
    }

    public func makeService(instanceID: UUID, configJSON: Data, shell: any WidgetShellContext) -> (any WidgetService)? {
        makeServiceClosure(instanceID, configJSON, shell)
    }
}
