import CoreGraphics

/// Pure geometry for placing and drawing a border around a target window.
/// Kept free of AppKit so it can be unit tested.
public enum BorderGeometry {
    /// Converts a rect from CoreGraphics screen coordinates (origin at the
    /// top-left of the primary display, y down) — the space the Accessibility
    /// API reports in — to AppKit screen coordinates (origin bottom-left, y up).
    public static func appKitRect(fromCG rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: primaryScreenHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    /// The overlay window's frame: the target window frame expanded by the
    /// border width on every side, so the border is drawn outside the window.
    public static func overlayFrame(forWindowFrame frame: CGRect, borderWidth: CGFloat) -> CGRect {
        frame.insetBy(dx: -borderWidth, dy: -borderWidth)
    }

    /// Stroke parameters for the border ring, in the overlay's local
    /// coordinates. The stroke centerline is inset half a border width from
    /// the overlay edge, so the ring's inner edge lands exactly on the target
    /// window edge and its inner corner radius matches `innerRadius`.
    public struct Ring: Equatable {
        public let rect: CGRect
        public let cornerRadius: CGFloat
        public let lineWidth: CGFloat
    }

    public static func ring(overlaySize: CGSize, borderWidth: CGFloat, innerRadius: CGFloat) -> Ring {
        let rect = CGRect(origin: .zero, size: overlaySize)
            .insetBy(dx: borderWidth / 2, dy: borderWidth / 2)
        let radius = innerRadius > 0 ? innerRadius + borderWidth / 2 : 0
        // CGPath requires the corner radius to fit within the rect.
        let clamped = min(radius, min(rect.width, rect.height) / 2)
        return Ring(rect: rect, cornerRadius: max(0, clamped), lineWidth: borderWidth)
    }

    /// A window whose frame covers an entire screen (native fullscreen or a
    /// borderless fullscreen app) should not get a border.
    public static func coversScreen(windowFrame: CGRect, screenFrames: [CGRect]) -> Bool {
        screenFrames.contains { screen in
            windowFrame.origin.x <= screen.origin.x + 1
                && windowFrame.origin.y <= screen.origin.y + 1
                && windowFrame.maxX >= screen.maxX - 1
                && windowFrame.maxY >= screen.maxY - 1
        }
    }

    /// Windows below this size are palettes/popovers, not user windows.
    public static let minimumBorderableSize = CGSize(width: 64, height: 64)

    public static func isBorderable(size: CGSize) -> Bool {
        size.width >= minimumBorderableSize.width && size.height >= minimumBorderableSize.height
    }
}
