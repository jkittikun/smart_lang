import AppKit

/// The menu-bar icon: a small ก top-left and A bottom-right with two corner
/// arrows (echoing the app icon). Drawn in code as a template image, so macOS
/// tints it for light and dark menu bars.
enum StatusIcon {
    static let size = NSSize(width: 21, height: 22)

    static let normal = make(inverted: false)
    /// Filled rounded square with the glyphs cut out, used for the flash.
    static let inverted = make(inverted: true)

    private static func make(inverted: Bool) -> NSImage {
        let image = NSImage(size: size, flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            NSColor.black.setFill()
            NSColor.black.setStroke()
            if inverted {
                NSBezierPath(roundedRect: rect.insetBy(dx: 0.25, dy: 0.25), xRadius: 4.5, yRadius: 4.5).fill()
                ctx.setBlendMode(.destinationOut) // everything below punches holes
            }
            drawGlyphs()
            drawArrows()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "SmartLang"
        return image
    }

    private static func drawGlyphs() {
        let thai = NSFont(name: "Thonburi-Bold", size: 13) ?? NSFont.boldSystemFont(ofSize: 13)
        let latin = NSFont.systemFont(ofSize: 11, weight: .heavy)
        draw("ก", font: thai, x: 0.5, baseline: 10.5)
        draw("A", font: latin, x: 11.5, baseline: 20.5)
    }

    /// Draws text with its baseline at `baseline` (flipped coordinates).
    private static func draw(_ text: String, font: NSFont, x: CGFloat, baseline: CGFloat) {
        let attributed = NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: NSColor.black])
        attributed.draw(at: NSPoint(x: x, y: baseline - font.ascender))
    }

    private static func drawArrows() {
        let lineWidth: CGFloat = 1.3
        // Top-right: across, then down towards A.
        let top = NSBezierPath()
        top.move(to: NSPoint(x: 12, y: 3.5))
        top.line(to: NSPoint(x: 17, y: 3.5))
        top.line(to: NSPoint(x: 17, y: 7))
        stroke(top, width: lineWidth)
        head(tip: NSPoint(x: 17, y: 10), pointingDown: true)
        // Bottom-left: across, then up towards ก.
        let bottom = NSBezierPath()
        bottom.move(to: NSPoint(x: 9, y: 19.5))
        bottom.line(to: NSPoint(x: 3.5, y: 19.5))
        bottom.line(to: NSPoint(x: 3.5, y: 16))
        stroke(bottom, width: lineWidth)
        head(tip: NSPoint(x: 3.5, y: 13), pointingDown: false)
    }

    private static func stroke(_ path: NSBezierPath, width: CGFloat) {
        path.lineWidth = width
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        path.stroke()
    }

    private static func head(tip: NSPoint, pointingDown: Bool) {
        let dy: CGFloat = pointingDown ? -3.4 : 3.4
        let path = NSBezierPath()
        path.move(to: tip)
        path.line(to: NSPoint(x: tip.x - 2.4, y: tip.y + dy))
        path.line(to: NSPoint(x: tip.x + 2.4, y: tip.y + dy))
        path.close()
        path.fill()
    }
}
