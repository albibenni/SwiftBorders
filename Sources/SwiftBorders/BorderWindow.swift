import AppKit
import SwiftBordersCore

/// A click-through overlay panel that draws one border ring.
///
/// Deliberate choices for macOS 15/26 reliability:
/// - `.transient` + `.ignoresCycle` collection behavior keeps Sequoia's
///   built-in window tiling, Mission Control and Cmd-Tab from treating the
///   border as a real window (the JankyBorders #115 failure mode).
/// - `.fullScreenAuxiliary` lets the border appear over fullscreen spaces.
/// - A static CAShapeLayer with implicit animations disabled means zero
///   GPU work while nothing changes (the JankyBorders #188 Tahoe issue was
///   continuous redrawing).
@MainActor
final class BorderWindow: NSPanel {
    private let shape = CAShapeLayer()

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        level = .normal
        collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary, .canJoinAllSpaces]

        let view = NSView()
        view.wantsLayer = true
        contentView = view
        shape.fillColor = nil
        shape.actions = [
            "path": NSNull(), "position": NSNull(), "bounds": NSNull(),
            "strokeColor": NSNull(), "lineWidth": NSNull(), "hidden": NSNull(),
        ]
        view.layer?.addSublayer(shape)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Places the overlay around `targetFrame` (AppKit screen coordinates)
    /// and redraws the ring. Cheap enough to call on every AX move event.
    func render(targetFrame: CGRect, width: CGFloat, innerRadius: CGFloat, color: CGColor) {
        let overlay = BorderGeometry.overlayFrame(forWindowFrame: targetFrame, borderWidth: width)
        setFrame(overlay, display: false)

        let ring = BorderGeometry.ring(
            overlaySize: overlay.size, borderWidth: width, innerRadius: innerRadius)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.frame = CGRect(origin: .zero, size: overlay.size)
        shape.lineWidth = ring.lineWidth
        shape.strokeColor = color
        shape.path = ring.cornerRadius > 0
            ? CGPath(
                roundedRect: ring.rect,
                cornerWidth: ring.cornerRadius,
                cornerHeight: ring.cornerRadius,
                transform: nil)
            : CGPath(rect: ring.rect, transform: nil)
        CATransaction.commit()
    }

    /// Stacks the border directly against its target window so unrelated
    /// windows layer correctly in between. `NSWindow.order(_:relativeTo:)`
    /// accepts window numbers of other processes' windows.
    func stack(relativeTo targetWindowID: CGWindowID, order: Config.Order) {
        self.order(order == .above ? .above : .below, relativeTo: Int(targetWindowID))
    }
}
