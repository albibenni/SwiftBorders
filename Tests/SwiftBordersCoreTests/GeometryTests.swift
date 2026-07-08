import CoreGraphics
import Testing

@testable import SwiftBordersCore

@Suite("Border geometry")
struct GeometryTests {
    @Test func convertsCGToAppKitCoordinates() {
        // A 800x600 window at CG (100, 50) on a 1440-point-tall primary display:
        // its top is 50 from the screen top, so its bottom is 1440-650 in AppKit.
        let cg = CGRect(x: 100, y: 50, width: 800, height: 600)
        let appKit = BorderGeometry.appKitRect(fromCG: cg, primaryScreenHeight: 1440)
        #expect(appKit == CGRect(x: 100, y: 790, width: 800, height: 600))
    }

    @Test func conversionIsItsOwnInverse() {
        let cg = CGRect(x: -300, y: 120, width: 500, height: 400)  // secondary display, left of primary
        let roundTrip = BorderGeometry.appKitRect(
            fromCG: BorderGeometry.appKitRect(fromCG: cg, primaryScreenHeight: 1440),
            primaryScreenHeight: 1440)
        #expect(roundTrip == cg)
    }

    @Test func overlayExpandsWindowFrameOnAllSides() {
        let frame = CGRect(x: 10, y: 20, width: 100, height: 80)
        let overlay = BorderGeometry.overlayFrame(forWindowFrame: frame, borderWidth: 5)
        #expect(overlay == CGRect(x: 5, y: 15, width: 110, height: 90))
    }

    @Test func ringInnerEdgeLandsOnWindowEdge() {
        let overlay = BorderGeometry.overlayFrame(
            forWindowFrame: CGRect(x: 0, y: 0, width: 100, height: 80), borderWidth: 6)
        let ring = BorderGeometry.ring(overlaySize: overlay.size, borderWidth: 6, innerRadius: 16)
        // Stroke centerline inset by width/2: inner edge = centerline + width/2 = window edge.
        #expect(ring.rect == CGRect(x: 3, y: 3, width: 106, height: 86))
        #expect(ring.lineWidth == 6)
        // Centerline radius = inner radius + width/2, so the inner arc matches
        // the window's own corner radius.
        #expect(ring.cornerRadius == 19)
    }

    @Test func squareRingHasNoCornerRadius() {
        let ring = BorderGeometry.ring(
            overlaySize: CGSize(width: 110, height: 90), borderWidth: 5, innerRadius: 0)
        #expect(ring.cornerRadius == 0)
    }

    @Test func cornerRadiusIsClampedForTinyWindows() {
        let ring = BorderGeometry.ring(
            overlaySize: CGSize(width: 70, height: 70), borderWidth: 5, innerRadius: 100)
        #expect(ring.cornerRadius <= min(ring.rect.width, ring.rect.height) / 2)
        #expect(ring.cornerRadius > 0)
    }

    @Test func fullscreenWindowsCoverTheirScreen() {
        let screens = [
            CGRect(x: 0, y: 0, width: 1512, height: 982),
            CGRect(x: 1512, y: 0, width: 2560, height: 1440),
        ]
        #expect(BorderGeometry.coversScreen(
            windowFrame: CGRect(x: 0, y: 0, width: 1512, height: 982), screenFrames: screens))
        // Off-by-fraction frames (menu bar animations) still count as covering.
        #expect(BorderGeometry.coversScreen(
            windowFrame: CGRect(x: 0.5, y: 0, width: 1511.5, height: 982), screenFrames: screens))
        #expect(!BorderGeometry.coversScreen(
            windowFrame: CGRect(x: 100, y: 100, width: 800, height: 600), screenFrames: screens))
    }

    @Test func tinyWindowsAreNotBorderable() {
        #expect(!BorderGeometry.isBorderable(size: CGSize(width: 40, height: 40)))
        #expect(BorderGeometry.isBorderable(size: CGSize(width: 400, height: 300)))
    }
}
