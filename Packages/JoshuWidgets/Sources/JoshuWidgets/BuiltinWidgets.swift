import JoshuKit

/// Registry entry point for the built-in widget types.
/// Grows as widgets land: Coding (M6), Reviewer (M7), Meeting (M8b).
public enum BuiltinWidgets {
    @MainActor
    public static var all: [AnyWidgetDescriptor] {
        [
            AnyWidgetDescriptor(CodingWidget.self),
            AnyWidgetDescriptor(ReviewerWidget.self),
            AnyWidgetDescriptor(MeetingWidget.self),
            AnyWidgetDescriptor(NotesWidget.self),
            AnyWidgetDescriptor(ChatHeadsWidget.self),
        ]
    }
}
