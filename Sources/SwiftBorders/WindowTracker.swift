import AppKit
import ApplicationServices
import SwiftBordersCore

struct TrackedWindow {
    let id: CGWindowID
    let element: AXUIElement
    let pid: pid_t
    let appName: String?
    /// Window frame in CG coordinates (top-left origin).
    var frame: CGRect
    var hasToolbar: Bool
}

@MainActor
protocol WindowTrackerDelegate: AnyObject {
    func trackerDidAdd(_ window: TrackedWindow)
    func trackerDidRemove(id: CGWindowID)
    func trackerDidMove(id: CGWindowID, frame: CGRect)
    func trackerDidChangeFocus(to id: CGWindowID?)
    func trackerDidReconcile(onScreen: Set<CGWindowID>)
}

/// Tracks every bordered window through public APIs only: per-app AXObservers
/// for events, NSWorkspace notifications for app/space lifecycle, and a
/// periodic CGWindowList reconciliation pass that corrects anything a missed
/// event left stale — reliability comes from that self-healing loop, not from
/// trusting each individual notification.
@MainActor
final class WindowTracker {
    weak var delegate: WindowTrackerDelegate?

    private(set) var windows: [CGWindowID: TrackedWindow] = [:]
    private(set) var focusedID: CGWindowID?

    private var appObservers: [pid_t: AXObserver] = [:]
    private var appElements: [pid_t: AXUIElement] = [:]
    private var pollers: [CGWindowID: Poller] = [:]
    private var reconcileTimer: Timer?
    private var reconcileTick = 0
    private var allowsApp: (String?) -> Bool

    private static let windowNotifications = [
        kAXUIElementDestroyedNotification,
        kAXWindowMovedNotification,
        kAXWindowResizedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
    ]

    init(allowsApp: @escaping (String?) -> Bool) {
        self.allowsApp = allowsApp
    }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(
            self, selector: #selector(appLaunched(_:)),
            name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        center.addObserver(
            self, selector: #selector(appTerminated(_:)),
            name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        center.addObserver(
            self, selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil)
        center.addObserver(
            self, selector: #selector(spaceChanged(_:)),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)

        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            addApp(app)
        }
        updateFocus()
        reconcile()

        let timer = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reconcile() }
        }
        RunLoop.main.add(timer, forMode: .common)
        reconcileTimer = timer
    }

    func updateFilter(allowsApp: @escaping (String?) -> Bool) {
        self.allowsApp = allowsApp
        // Drop windows of now-excluded apps; a rescan picks up newly allowed ones.
        for window in windows.values where !allowsApp(window.appName) {
            remove(id: window.id)
        }
        rescanAllApps()
    }

    // MARK: - App lifecycle

    private func addApp(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard pid != ProcessInfo.processInfo.processIdentifier,
              appObservers[pid] == nil,
              allowsApp(app.localizedName) else { return }

        var observer: AXObserver?
        guard AXObserverCreate(pid, axObserverCallback, &observer) == .success,
              let observer else { return }

        let appElement = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for notification in [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification] {
            AXObserverAddNotification(observer, appElement, notification as CFString, refcon)
        }
        CFRunLoopAddSource(
            CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)

        appObservers[pid] = observer
        appElements[pid] = appElement
        for window in AX.windows(ofApp: appElement) {
            track(windowElement: window, pid: pid, appName: app.localizedName)
        }
    }

    private func removeApp(pid: pid_t) {
        if let observer = appObservers.removeValue(forKey: pid) {
            CFRunLoopRemoveSource(
                CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }
        appElements.removeValue(forKey: pid)
        for id in windows.values.filter({ $0.pid == pid }).map(\.id) {
            remove(id: id)
        }
    }

    @objc private func appLaunched(_ note: Notification) {
        guard let app = runningApp(from: note), app.activationPolicy == .regular else { return }
        addApp(app)
        // Apps often finish creating their AX hierarchy after launch; retry once.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self, let element = self.appElements[app.processIdentifier] else { return }
            for window in AX.windows(ofApp: element) {
                self.track(windowElement: window, pid: app.processIdentifier, appName: app.localizedName)
            }
        }
    }

    @objc private func appTerminated(_ note: Notification) {
        guard let app = runningApp(from: note) else { return }
        removeApp(pid: app.processIdentifier)
    }

    @objc private func appActivated(_ note: Notification) {
        updateFocus()
        reconcile()
    }

    @objc private func spaceChanged(_ note: Notification) {
        reconcile()
    }

    private func runningApp(from note: Notification) -> NSRunningApplication? {
        note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    }

    // MARK: - Window tracking

    private func track(windowElement: AXUIElement, pid: pid_t, appName: String?) {
        guard let id = AX.windowID(of: windowElement), windows[id] == nil else { return }
        guard AX.role(of: windowElement) == kAXWindowRole else { return }
        let subrole = AX.subrole(of: windowElement)
        guard subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole else { return }
        guard let frame = AX.frame(of: windowElement),
              BorderGeometry.isBorderable(size: frame.size) else { return }

        guard let observer = appObservers[pid] else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for notification in Self.windowNotifications {
            AXObserverAddNotification(observer, windowElement, notification as CFString, refcon)
        }

        let window = TrackedWindow(
            id: id, element: windowElement, pid: pid, appName: appName,
            frame: frame, hasToolbar: AX.hasToolbar(windowElement))
        windows[id] = window
        delegate?.trackerDidAdd(window)
        updateFocus()
    }

    private func remove(id: CGWindowID) {
        guard windows.removeValue(forKey: id) != nil else { return }
        pollers.removeValue(forKey: id)?.stop()
        let wasFocused = (focusedID == id)
        if wasFocused {
            focusedID = nil
            delegate?.trackerDidChangeFocus(to: nil)
        }
        delegate?.trackerDidRemove(id: id)
        if wasFocused {
            DispatchQueue.main.async { [weak self] in
                self?.updateFocus()
            }
        }
    }

    // MARK: - AX events

    fileprivate func handle(notification: String, element: AXUIElement) {
        switch notification {
        case kAXWindowCreatedNotification:
            var pid = pid_t(0)
            guard AXUIElementGetPid(element, &pid) == .success else { return }
            let name = NSRunningApplication(processIdentifier: pid)?.localizedName
            guard allowsApp(name) else { return }
            track(windowElement: element, pid: pid, appName: name)

        case kAXUIElementDestroyedNotification:
            // A destroyed element no longer resolves to a window ID; find it
            // by identity instead.
            if let id = AX.windowID(of: element) ?? windows.values.first(
                where: { CFEqual($0.element, element) })?.id {
                remove(id: id)
            }

        case kAXWindowMovedNotification, kAXWindowResizedNotification:
            guard let id = AX.windowID(of: element), windows[id] != nil else { return }
            refreshFrame(id: id)
            // AX move events can be sparse during a live drag; poll briefly at
            // high frequency until the frame stops changing so the border
            // follows the window smoothly, then go fully idle again.
            beginPolling(id: id)

        case kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification:
            reconcile()

        case kAXFocusedWindowChangedNotification:
            if let id = AX.windowID(of: element) {
                updateFocus(explicitID: id)
            } else {
                updateFocus()
            }

        default:
            break
        }
    }

    private func refreshFrame(id: CGWindowID) {
        guard var window = windows[id], let frame = AX.frame(of: window.element) else { return }
        guard frame != window.frame else { return }
        window.frame = frame
        windows[id] = window
        delegate?.trackerDidMove(id: id, frame: frame)
    }

    private func updateFocus(explicitID: CGWindowID? = nil) {
        var newFocus: CGWindowID?
        if let explicitID = explicitID, windows[explicitID] != nil {
            newFocus = explicitID
        } else if let app = NSWorkspace.shared.frontmostApplication,
           let appElement = appElements[app.processIdentifier],
           let focused = AX.focusedWindow(ofApp: appElement),
           let id = AX.windowID(of: focused), windows[id] != nil {
            newFocus = id
        }
        guard newFocus != focusedID else { return }
        focusedID = newFocus
        delegate?.trackerDidChangeFocus(to: newFocus)
    }

    // MARK: - Drag polling

    @MainActor
    private final class Poller: NSObject {
        var displayLink: CADisplayLink?
        var fallbackTimer: Timer?
        var lastChange = Date()
        let id: CGWindowID
        weak var tracker: WindowTracker?

        init(id: CGWindowID, tracker: WindowTracker) {
            self.id = id
            self.tracker = tracker
            super.init()
        }

        func start() {
            if let screen = NSScreen.main ?? NSScreen.screens.first {
                let link = screen.displayLink(target: self, selector: #selector(tick))
                link.add(to: .main, forMode: .common)
                self.displayLink = link
            } else {
                let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        self?.tick()
                    }
                }
                RunLoop.main.add(timer, forMode: .common)
                self.fallbackTimer = timer
            }
        }

        @objc private func tick() {
            Task { @MainActor in
                tracker?.poll(id: id)
            }
        }

        func stop() {
            displayLink?.invalidate()
            displayLink = nil
            fallbackTimer?.invalidate()
            fallbackTimer = nil
        }
    }

    private func beginPolling(id: CGWindowID) {
        if let existing = pollers[id] {
            existing.lastChange = Date()
            return
        }
        let poller = Poller(id: id, tracker: self)
        pollers[id] = poller
        poller.start()
    }

    private func poll(id: CGWindowID) {
        guard let poller = pollers[id], let window = windows[id] else {
            pollers.removeValue(forKey: id)?.stop()
            return
        }
        if let frame = AX.frame(of: window.element), frame != window.frame {
            refreshFrame(id: id)
            poller.lastChange = Date()
        } else if Date().timeIntervalSince(poller.lastChange) > 0.35 {
            pollers.removeValue(forKey: id)?.stop()
        }
    }

    // MARK: - Reconciliation

    /// Self-healing pass: CGWindowList is the ground truth for what is
    /// actually on screen (current space, not minimized, not hidden).
    private func reconcile() {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var onScreen = Set<CGWindowID>()
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        if let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] {
            for entry in list {
                guard let layer = entry[kCGWindowLayer as String] as? Int, layer == 0,
                      let pid = entry[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                      let id = entry[kCGWindowNumber as String] as? CGWindowID else { continue }
                onScreen.insert(id)
            }
        }

        // Windows that vanished entirely (missed destroy events) get dropped
        // once CGWindowList no longer knows them at all.
        let allIDs = (CGWindowListCopyWindowInfo(.excludeDesktopElements, kCGNullWindowID)
            as? [[String: Any]])?
            .compactMap { $0[kCGWindowNumber as String] as? CGWindowID } ?? []
        let known = Set(allIDs)
        for id in windows.keys where !known.contains(id) {
            remove(id: id)
        }

        for id in windows.keys.filter({ onScreen.contains($0) }) {
            refreshFrame(id: id)
        }
        delegate?.trackerDidReconcile(onScreen: onScreen)

        updateFocus()

        reconcileTick += 1
        if reconcileTick % 3 == 0 {
            rescanAllApps()
        }
    }

    /// Catches windows whose creation event was missed and apps launched
    /// before accessibility was granted.
    private func rescanAllApps() {
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let pid = app.processIdentifier
            if appObservers[pid] == nil {
                addApp(app)
            } else if let element = appElements[pid] {
                for window in AX.windows(ofApp: element) {
                    track(windowElement: window, pid: pid, appName: app.localizedName)
                }
            }
        }
    }
}

/// C callback trampoline: AXObserver delivers on the run loop we registered
/// (the main run loop), so hopping straight onto the main actor is safe.
private let axObserverCallback: AXObserverCallback = { _, element, notification, refcon in
    guard let refcon else { return }
    let tracker = Unmanaged<WindowTracker>.fromOpaque(refcon).takeUnretainedValue()
    let name = notification as String
    MainActor.assumeIsolated {
        tracker.handle(notification: name, element: element)
    }
}
