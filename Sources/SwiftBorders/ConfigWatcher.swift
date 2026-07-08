import Foundation
import SwiftBordersCore

/// Watches the config file and calls back on change, so a running instance
/// picks up edits live (SwiftBorders' replacement for JankyBorders' IPC).
/// Editors replace files atomically, so the watch re-arms after delete/rename.
@MainActor
final class ConfigWatcher {
    private let url: URL
    private let onChange: () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var pendingReload: DispatchWorkItem?

    init(url: URL, onChange: @escaping () -> Void) {
        self.url = url
        self.onChange = onChange
        arm()
    }

    private func arm() {
        source?.cancel()
        source = nil
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else {
            // File doesn't exist (yet); check again later so creating it
            // starts live reloading without a restart.
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.arm() }
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend],
            queue: .main)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            let events = source.data
            self.scheduleReload()
            if events.contains(.delete) || events.contains(.rename) {
                self.arm()
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    /// Debounce: editors emit several events per save.
    private func scheduleReload() {
        pendingReload?.cancel()
        let work = DispatchWorkItem { [onChange] in onChange() }
        pendingReload = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
}
