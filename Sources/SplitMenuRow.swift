import AppKit

// A menu row holding two actions side by side, each highlighted on hover the way a menu item is.
final class SplitMenuRow: NSView {
    var leftTitle = "" { didSet { needsDisplay = true } }
    var rightTitle = "" { didSet { needsDisplay = true } }
    var showsRight = true { didSet { needsDisplay = true } }
    var onLeft: () -> Void = {}
    var onRight: () -> Void = {}

    private enum Side { case left, right }
    private var hovered: Side? { didSet { if hovered != oldValue { needsDisplay = true } } }
    private let font = NSFont.menuFont(ofSize: 0)
    private let inset: CGFloat = 5, textLeading: CGFloat = 17, textTrailing: CGFloat = 10

    init(width: CGFloat = 200) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 22))
        autoresizingMask = .width
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var rightRect: NSRect {
        guard showsRight else { return .zero }
        let width = (rightTitle as NSString).size(withAttributes: [.font: font]).width + textTrailing * 2
        return NSRect(x: bounds.maxX - inset - width, y: bounds.minY, width: width, height: bounds.height)
    }

    private var leftRect: NSRect {
        NSRect(x: bounds.minX + inset, y: bounds.minY, width: (showsRight ? rightRect.minX : bounds.maxX - inset) - bounds.minX - inset, height: bounds.height)
    }

    private func side(at point: NSPoint) -> Side? {
        if rightRect.contains(point) { return .right }
        return leftRect.contains(point) ? .left : nil
    }

    override func draw(_ dirtyRect: NSRect) {
        for (side, rect, title, color) in [(Side.left, leftRect, leftTitle, NSColor.labelColor), (.right, rightRect, rightTitle, .secondaryLabelColor)] where !rect.isEmpty {
            let highlighted = hovered == side
            if highlighted {
                NSColor.selectedContentBackgroundColor.setFill()
                NSBezierPath(roundedRect: rect.insetBy(dx: 0, dy: 1), xRadius: 5, yRadius: 5).fill()
            }
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: highlighted ? NSColor.selectedMenuItemTextColor : color]
            let size = (title as NSString).size(withAttributes: attributes)
            let x = side == .left ? rect.minX + textLeading - inset : rect.maxX - textTrailing - size.width
            (title as NSString).draw(at: NSPoint(x: x, y: rect.midY - size.height / 2), withAttributes: attributes)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways], owner: self))
    }

    override func mouseMoved(with event: NSEvent) { hovered = side(at: convert(event.locationInWindow, from: nil)) }
    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseExited(with event: NSEvent) { hovered = nil }

    override func mouseUp(with event: NSEvent) {
        let clicked = side(at: convert(event.locationInWindow, from: nil))
        hovered = nil
        guard let clicked else { return }
        enclosingMenuItem?.menu?.cancelTracking()
        clicked == .left ? onLeft() : onRight()
    }
}
