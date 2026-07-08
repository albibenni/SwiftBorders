import CoreGraphics
import Testing

@testable import SwiftBordersCore

@Suite("Config parsing")
struct ConfigTests {
    @Test func defaults() {
        let config = Config.load(cliArguments: [], fileContents: "")
        #expect(config.width == 5.0)
        #expect(config.style == .round)
        #expect(config.order == .below)
        #expect(config.radius == .auto)
        #expect(config.warnings.isEmpty)
    }

    @Test func parsesCLIArguments() {
        let config = Config.load(
            cliArguments: ["width=8", "style=square", "order=above", "radius=12.5"],
            fileContents: "")
        #expect(config.width == 8)
        #expect(config.style == .square)
        #expect(config.order == .above)
        #expect(config.radius == .fixed(12.5))
    }

    @Test func cliOverridesFile() {
        let file = """
        # comment line
        width=3

        order=above
        """
        let config = Config.load(cliArguments: ["width=10"], fileContents: file)
        #expect(config.width == 10)
        #expect(config.order == .above)
        #expect(config.warnings.isEmpty)
    }

    @Test func collectsWarningsForBadInput() {
        let config = Config.load(
            cliArguments: ["width=-2", "style=fancy", "noequals", "bogus_key=1"],
            fileContents: "")
        #expect(config.warnings.count == 4)
        #expect(config.width == 5.0, "bad value must not clobber the default")
        #expect(config.style == .round)
    }

    @Test func jankyBordersCompatKeysAreSilentlyAccepted() {
        let config = Config.load(cliArguments: ["hidpi=on", "ax_focus=on"], fileContents: "")
        #expect(config.warnings.isEmpty)
    }

    @Test func parsesColors() throws {
        let config = Config.load(cliArguments: ["active_color=0x80FF0000"], fileContents: "")
        let components = try #require(config.activeColor.components)
        #expect(abs(components[0] - 1.0) < 0.001)  // red
        #expect(abs(components[1] - 0.0) < 0.001)  // green
        #expect(abs(components[2] - 0.0) < 0.001)  // blue
        #expect(abs(config.activeColor.alpha - 128.0 / 255.0) < 0.001)
    }

    @Test(arguments: ["0xGGGGGGGG", "ff0000", "0xfff", "", "red"])
    func rejectsBadColors(hex: String) {
        #expect(Config.color(fromHexString: hex) == nil)
    }

    @Test func blacklistBlocksCaseInsensitively() {
        let config = Config.load(cliArguments: ["blacklist=Safari, Music"], fileContents: "")
        #expect(!config.allowsApp(named: "safari"))
        #expect(!config.allowsApp(named: "Music"))
        #expect(config.allowsApp(named: "Terminal"))
        #expect(config.allowsApp(named: nil))
    }

    @Test func whitelistWinsOverBlacklist() {
        let config = Config.load(
            cliArguments: ["whitelist=Terminal", "blacklist=Terminal"], fileContents: "")
        #expect(config.allowsApp(named: "Terminal"))
        #expect(!config.allowsApp(named: "Safari"))
        #expect(!config.allowsApp(named: nil))
    }

    @Test func autoRadiusMatchesOSAndWindowStyle() {
        let config = Config.load(cliArguments: [], fileContents: "")
        // Tahoe: toolbar windows are rounder than titlebar-only windows.
        #expect(config.innerRadius(windowHasToolbar: true, osMajorVersion: 26) == 26)
        #expect(config.innerRadius(windowHasToolbar: false, osMajorVersion: 26) == 16)
        // Pre-Tahoe: uniform radius.
        #expect(config.innerRadius(windowHasToolbar: true, osMajorVersion: 15) == 11)
    }

    @Test func fixedRadiusAndSquareStyleOverrideAuto() {
        var config = Config.load(cliArguments: ["radius=4"], fileContents: "")
        #expect(config.innerRadius(windowHasToolbar: true, osMajorVersion: 26) == 4)
        config = Config.load(cliArguments: ["style=square"], fileContents: "")
        #expect(config.innerRadius(windowHasToolbar: true, osMajorVersion: 26) == 0)
    }
}
