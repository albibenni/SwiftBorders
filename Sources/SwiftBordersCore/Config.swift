import Foundation
import CoreGraphics

/// Runtime configuration, parsed from `key=value` CLI arguments and the
/// optional config file at ~/.config/swiftborders/swiftbordersrc.
/// Keys are JankyBorders-compatible where they overlap.
public struct Config: Equatable {
    public enum Order: String, Equatable { case above, below }
    public enum Style: String, Equatable { case round, square }
    public enum Radius: Equatable {
        case auto
        case fixed(CGFloat)
    }

    public var activeColor: CGColor = Config.color(fromHex: 0xFFE1E3E4)!
    public var inactiveColor: CGColor = Config.color(fromHex: 0xFF494D64)!
    public var width: CGFloat = 5.0
    public var style: Style = .round
    public var radius: Radius = .auto
    public var order: Order = .below
    public var blacklist: Set<String> = []
    public var whitelist: Set<String> = []

    /// Warnings collected while parsing (unknown keys, malformed values).
    public private(set) var warnings: [String] = []

    public init() {}

    public static var configFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/swiftborders/swiftbordersrc")
    }

    /// File entries first, then CLI arguments so the CLI always wins.
    public static func load(cliArguments: [String], fileContents: String? = nil) -> Config {
        var config = Config()
        let text = fileContents ?? (try? String(contentsOf: configFileURL, encoding: .utf8))
        if let text {
            config.apply(pairs: Config.entries(fromFile: text))
        }
        config.apply(pairs: cliArguments)
        return config
    }

    static func entries(fromFile text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    public mutating func apply(pairs: [String]) {
        for pair in pairs {
            guard let eq = pair.firstIndex(of: "=") else {
                warnings.append("ignoring malformed option '\(pair)' (expected key=value)")
                continue
            }
            let key = String(pair[..<eq])
            let value = String(pair[pair.index(after: eq)...])
            apply(key: key, value: value)
        }
    }

    private mutating func apply(key: String, value: String) {
        switch key {
        case "active_color":
            if let c = Config.color(fromHexString: value) { activeColor = c } else { warnings.append("bad color '\(value)'") }
        case "inactive_color":
            if let c = Config.color(fromHexString: value) { inactiveColor = c } else { warnings.append("bad color '\(value)'") }
        case "width":
            if let w = Double(value), w > 0 { width = w } else { warnings.append("bad width '\(value)'") }
        case "style":
            if let s = Style(rawValue: value) { style = s } else { warnings.append("bad style '\(value)'") }
        case "radius":
            if value == "auto" {
                radius = .auto
            } else if let r = Double(value), r >= 0 {
                radius = .fixed(r)
            } else {
                warnings.append("bad radius '\(value)'")
            }
        case "order":
            if let o = Order(rawValue: value) { order = o } else { warnings.append("bad order '\(value)'") }
        case "blacklist":
            blacklist = Config.appNameList(value)
        case "whitelist":
            whitelist = Config.appNameList(value)
        case "hidpi", "background_color", "ax_focus", "blur_radius":
            break // accepted for JankyBorders compatibility; not needed here
        default:
            warnings.append("unknown option '\(key)'")
        }
    }

    private static func appNameList(_ value: String) -> Set<String> {
        Set(value.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty })
    }

    public func allowsApp(named name: String?) -> Bool {
        let lowered = (name ?? "").lowercased()
        if !whitelist.isEmpty { return whitelist.contains(lowered) }
        return !blacklist.contains(lowered)
    }

    /// Inner corner radius that should hug the target window's own corners.
    public func innerRadius(windowHasToolbar: Bool, osMajorVersion: Int) -> CGFloat {
        if style == .square { return 0 }
        switch radius {
        case .fixed(let r):
            return r
        case .auto:
            // macOS 26 (Tahoe) uses larger, style-dependent corner radii:
            // toolbar windows are noticeably rounder than titlebar-only ones.
            if osMajorVersion >= 26 {
                return windowHasToolbar ? 26 : 16
            }
            return 11
        }
    }

    // MARK: - Colors

    public static func color(fromHexString string: String) -> CGColor? {
        var hex = string.lowercased()
        if hex.hasPrefix("0x") { hex = String(hex.dropFirst(2)) }
        guard hex.count == 8, let value = UInt32(hex, radix: 16) else { return nil }
        return color(fromHex: value)
    }

    public static func color(fromHex value: UInt32) -> CGColor? {
        CGColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255.0,
            green: CGFloat((value >> 8) & 0xFF) / 255.0,
            blue: CGFloat(value & 0xFF) / 255.0,
            alpha: CGFloat((value >> 24) & 0xFF) / 255.0
        )
    }
}
