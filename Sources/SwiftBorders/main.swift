import AppKit
import ApplicationServices
import SwiftBordersCore

let cliArguments = Array(CommandLine.arguments.dropFirst())

if cliArguments.contains("--help") || cliArguments.contains("-h") {
    print("""
    swiftborders — window borders for macOS 15+, public APIs only

    usage: swiftborders [key=value ...]

      active_color=0xAARRGGBB    border color of the focused window
      inactive_color=0xAARRGGBB  border color of unfocused windows
      width=5.0                  border width in points
      style=round|square         corner style
      radius=auto|N              inner corner radius; auto matches the OS
      order=below|above          stack borders below or above their window
      blacklist=App1,App2        never border these apps
      whitelist=App1,App2        only border these apps

    Options can also live in ~/.config/swiftborders/swiftbordersrc
    (one key=value per line, # comments); the file is live-reloaded.
    Requires the Accessibility permission.
    """)
    exit(0)
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var manager: BorderManager?
    private var watcher: ConfigWatcher?
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        if AXIsProcessTrustedWithOptions(options as CFDictionary) {
            start()
        } else {
            info("waiting for Accessibility permission (System Settings → Privacy & Security → Accessibility)…")
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, AXIsProcessTrusted() else { return }
                    self.permissionTimer?.invalidate()
                    self.permissionTimer = nil
                    self.start()
                }
            }
        }
    }

    private func start() {
        let config = Config.load(cliArguments: cliArguments)
        config.warnings.forEach(warn)

        let manager = BorderManager(config: config)
        self.manager = manager
        manager.start()

        watcher = ConfigWatcher(url: Config.configFileURL) { [weak self] in
            let reloaded = Config.load(cliArguments: cliArguments)
            reloaded.warnings.forEach(warn)
            self?.manager?.apply(config: reloaded)
        }
        info("running (width=\(config.width), style=\(config.style.rawValue), order=\(config.order.rawValue))")
    }
}

signal(SIGINT) { _ in exit(0) }
signal(SIGTERM) { _ in exit(0) }

// Top-level code runs on the main thread; assumeIsolated bridges it onto the
// main actor for the AppKit setup.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
