import AppKit
import JoshuKit

extension NSScreen {
    /// Stable display UUID (survives reconnects; display ID does not).
    var displayUUIDString: String? {
        guard
            let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
            let cfUUID = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue(),
            let uuidString = CFUUIDCreateString(nil, cfUUID)
        else { return nil }
        return uuidString as String
    }

    var screenInfo: ScreenInfo {
        ScreenInfo(uuid: displayUUIDString, visibleFrame: visibleFrame)
    }

    static var allScreenInfos: [ScreenInfo] {
        screens.map(\.screenInfo)
    }
}
