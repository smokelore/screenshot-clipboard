import AppKit

// A menu row holding two actions side by side, each highlighted on hover the way a menu item is.
final class SplitMenuRow: NSView {
    var leftTitle = "" { didSet { needsDisplay = true } }
    var rightTitle = "" { didSet { needsDisplay = true } }
    var rightSymbol: String? { didSet { needsDisplay = true } }
    var showsRight = true { didSet { needsDisplay = true } }
    var onLeft: () -> Void = {}
    var onRight: () -> Void = {}

    private enum Side { case left, right }
    private var hovered: Side? { didSet { if hovered != oldValue { needsDisplay = true } } }
    private let font = NSFont.menuFont(ofSize: 0)
    // textLeading matches where macOS 26 starts standard item titles in a section without images or checkmarks.
    private let inset: CGFloat = 5, textLeading: CGFloat = 24, textTrailing: CGFloat = 10, symbolGap: CGFloat = 4

    private func symbol(_ color: NSColor) -> NSImage? {
        guard let rightSymbol else { return nil }
        let configuration = NSImage.SymbolConfiguration(pointSize: font.pointSize, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        return NSImage(systemSymbolName: rightSymbol, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
    }

    private var rightContentWidth: CGFloat {
        let text = (rightTitle as NSString).size(withAttributes: [.font: font]).width
        guard let image = symbol(.labelColor) else { return text }
        return image.size.width + symbolGap + text
    }

    init(width: CGFloat = 200) {
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 22))
        autoresizingMask = .width
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var rightRect: NSRect {
        guard showsRight else { return .zero }
        let width = rightContentWidth + textTrailing * 2
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
            let textColor = highlighted ? NSColor.selectedMenuItemTextColor : color
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
            let size = (title as NSString).size(withAttributes: attributes)
            var x = side == .left ? rect.minX + textLeading - inset : rect.maxX - textTrailing - rightContentWidth
            if side == .right, let image = symbol(textColor) {
                image.draw(in: NSRect(x: x, y: rect.midY - image.size.height / 2, width: image.size.width, height: image.size.height))
                x += image.size.width + symbolGap
            }
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
