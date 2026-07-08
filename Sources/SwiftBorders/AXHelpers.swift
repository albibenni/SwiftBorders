import AppKit
import ApplicationServices

/// The one non-public call in the project: maps an AXUIElement window to its
/// CGWindowID. Exported by ApplicationServices and stable since ~10.10; used
/// by Rectangle, AltTab, Loop, etc. Everything else here is public API.
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ identifier: UnsafeMutablePointer<CGWindowID>) -> AXError

enum AX {
    static func windowID(of element: AXUIElement) -> CGWindowID? {
        var id = CGWindowID(0)
        guard _AXUIElementGetWindow(element, &id) == .success, id != 0 else { return nil }
        return id
    }

    static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &ref) == .success else { return nil }
        return ref as? T
    }

    static func point(_ element: AXUIElement, _ name: String) -> CGPoint? {
        guard let value: AXValue = attribute(element, name) else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(value, .cgPoint, &point) else { return nil }
        return point
    }

    static func size(_ element: AXUIElement, _ name: String) -> CGSize? {
        guard let value: AXValue = attribute(element, name) else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(value, .cgSize, &size) else { return nil }
        return size
    }

    /// Window frame in CoreGraphics coordinates (origin at top-left of the
    /// primary display, y grows downward) — the coordinate space AX reports in.
    static func frame(of window: AXUIElement) -> CGRect? {
        guard let origin = point(window, kAXPositionAttribute),
              let size = size(window, kAXSizeAttribute) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    static func role(of element: AXUIElement) -> String? {
        attribute(element, kAXRoleAttribute)
    }

    static func subrole(of element: AXUIElement) -> String? {
        attribute(element, kAXSubroleAttribute)
    }

    private static func elements(_ list: [AnyObject]?) -> [AXUIElement] {
        (list ?? []).compactMap {
            guard CFGetTypeID($0) == AXUIElementGetTypeID() else { return nil }
            return ($0 as! AXUIElement)
        }
    }

    static func windows(ofApp appElement: AXUIElement) -> [AXUIElement] {
        let list: [AnyObject]? = attribute(appElement, kAXWindowsAttribute)
        return elements(list)
    }

    static func focusedWindow(ofApp appElement: AXUIElement) -> AXUIElement? {
        attribute(appElement, kAXFocusedWindowAttribute)
    }

    static func hasToolbar(_ window: AXUIElement) -> Bool {
        let children: [AnyObject]? = attribute(window, kAXChildrenAttribute)
        return elements(children).contains { role(of: $0) == "AXToolbar" }
    }

    static func isFullscreen(_ window: AXUIElement) -> Bool {
        (attribute(window, "AXFullScreen") as NSNumber?)?.boolValue ?? false
    }
}
