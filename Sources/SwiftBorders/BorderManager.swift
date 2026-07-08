import AppKit
import SwiftBordersCore

/// Owns one BorderWindow per tracked window and keeps them in sync with
/// tracker events and config reloads.
@MainActor
final class BorderManager: WindowTrackerDelegate {
    private var config: Config
    private var tracker: WindowTracker!
    private var borders: [CGWindowID: BorderWindow] = [:]
    private var onScreen: Set<CGWindowID> = []

    init(config: Config) {
        self.config = config
        self.tracker = WindowTracker(allowsApp: { [weak self] name in
            self?.config.allowsApp(named: name) ?? true
        })
        tracker.delegate = self
    }

    func start() {
        tracker.start()
    }

    func apply(config newConfig: Config) {
        config = newConfig
        tracker.updateFilter(allowsApp: { [weak self] name in
            self?.config.allowsApp(named: name) ?? true
        })
        for id in borders.keys {
            refresh(id: id)
        }
        info("configuration reloaded")
    }

    // MARK: - WindowTrackerDelegate

    func trackerDidAdd(_ window: TrackedWindow) {
        let border = BorderWindow()
        borders[window.id] = border
        // Newly created windows are on the active space by definition.
        onScreen.insert(window.id)
        refresh(id: window.id)
    }

    func trackerDidRemove(id: CGWindowID) {
        borders.removeValue(forKey: id)?.close()
        onScreen.remove(id)
    }

    func trackerDidMove(id: CGWindowID, frame: CGRect) {
        refresh(id: id, restack: false)
    }

    func trackerDidChangeFocus(to id: CGWindowID?) {
        for borderID in borders.keys {
            refresh(id: borderID, restack: borderID == id)
        }
    }

    func trackerDidReconcile(onScreen visible: Set<CGWindowID>) {
        onScreen = visible
        for id in borders.keys {
            refresh(id: id)
        }
    }

    // MARK: - Rendering

    private func refresh(id: CGWindowID, restack: Bool = true) {
        guard let border = borders[id], let window = tracker.windows[id] else { return }

        guard let primaryScreen = NSScreen.screens.first else { return }
        let targetFrame = BorderGeometry.appKitRect(
            fromCG: window.frame, primaryScreenHeight: primaryScreen.frame.maxY)

        let hidden = !onScreen.contains(id)
            || BorderGeometry.coversScreen(
                windowFrame: targetFrame, screenFrames: NSScreen.screens.map(\.frame))
        if hidden {
            border.orderOut(nil)
            return
        }

        let wasVisible = border.isVisible
        border.render(
            targetFrame: targetFrame,
            width: config.width,
            innerRadius: config.innerRadius(
                windowHasToolbar: window.hasToolbar,
                osMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion),
            color: id == tracker.focusedID ? config.activeColor : config.inactiveColor)
        if restack || !wasVisible {
            border.stack(relativeTo: id, order: config.order)
        }
    }
}
