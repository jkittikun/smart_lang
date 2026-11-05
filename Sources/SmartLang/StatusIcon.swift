import AppKit

/// The menu-bar icon, drawn in code as a template image so macOS tints it for
/// light and dark menu bars. Each style also has an inverted version (filled
/// rounded square with the glyphs cut out) used for the flash.
enum StatusIcon {
    enum Style: String, CaseIterable, Identifiable {
        case diagonal   // small ก top-left, A bottom-right, corner arrows (like the app icon)
        case compact    // ก ⇄ A with short arrows
        case underline  // ก A with a ↔ underneath

        var id: String { rawValue }

        var title: String {
            switch self {
            case .diagonal: return "Diagonal (like the app icon)"
            case .compact: return "ก ⇄ A, short arrows"
            case .underline: return "ก A, arrow underneath"
            }
        }

        var width: CGFloat {
            switch self {
            case .diagonal: return 21
            case .compact: return 31
            case .underline: return 23
            }
        }
    }

    static let height: CGFloat = 22
    private static var cache: [String: NSImage] = [:]

    static func image(_ style: Style, inverted: Bool = false) -> NSImage {
        let key = "\(style.rawValue)-\(inverted)"
        if let cached = cache[key] { return cached }
        let size = NSSize(width: style.width, height: height)
        let image = NSImage(size: size, flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            NSColor.black.setFill()
            NSColor.black.setStroke()
            if inverted {
                NSBezierPath(roundedRect: rect.insetBy(dx: 0.25, dy: 0.25), xRadius: 4.5, yRadius: 4.5).fill()
                ctx.setBlendMode(.destinationOut) // everything below punches holes
            }
            switch style {
            case .diagonal: drawDiagonal()
            case .compact: drawCompact()
            case .underline: drawUnderline()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "SmartLang"
        cache[key] = image
        return image
    }

    // MARK: Styles

    private static func drawDiagonal() {
        text("ก", font: thaiFont(13), x: 0.5, baseline: 10.5)
        text("A", font: latinFont(11), x: 11.5, baseline: 20.5)
        // Top-right: across, then down towards A.
        polyline([NSPoint(x: 12, y: 3.5), NSPoint(x: 17, y: 3.5), NSPoint(x: 17, y: 7)])
        head(tip: NSPoint(x: 17, y: 10), direction: .down)
        // Bottom-left: across, then up towards ก.
        polyline([NSPoint(x: 9, y: 19.5), NSPoint(x: 3.5, y: 19.5), NSPoint(x: 3.5, y: 16)])
        head(tip: NSPoint(x: 3.5, y: 13), direction: .up)
    }

    private static func drawCompact() {
        text("ก", font: thaiFont(15), x: 0.5, baseline: 16)
        text("A", font: latinFont(13), x: 19.5, baseline: 16)
        // ⇄ : upper arrow points right, lower arrow points left.
        polyline([NSPoint(x: 11.5, y: 9), NSPoint(x: 15.5, y: 9)])
        head(tip: NSPoint(x: 18, y: 9), direction: .right, size: 2.2)
        polyline([NSPoint(x: 14, y: 13), NSPoint(x: 18, y: 13)])
        head(tip: NSPoint(x: 11.5, y: 13), direction: .left, size: 2.2)
    }

    private static func drawUnderline() {
        text("ก", font: thaiFont(15), x: 0.5, baseline: 15)
        text("A", font: latinFont(13), x: 12, baseline: 15)
        // ↔ under both letters.
        polyline([NSPoint(x: 5.5, y: 19), NSPoint(x: 16.5, y: 19)])
        head(tip: NSPoint(x: 3.5, y: 19), direction: .left, size: 2.2)
        head(tip: NSPoint(x: 18.5, y: 19), direction: .right, size: 2.2)
    }

    // MARK: Drawing helpers

    private static func thaiFont(_ size: CGFloat) -> NSFont {
        NSFont(name: "Thonburi-Bold", size: size) ?? NSFont.boldSystemFont(ofSize: size)
    }

    private static func latinFont(_ size: CGFloat) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: .heavy)
    }

    /// Draws text with its baseline at `baseline` (flipped coordinates).
    private static func text(_ string: String, font: NSFont, x: CGFloat, baseline: CGFloat) {
        let attributed = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: NSColor.black])
        attributed.draw(at: NSPoint(x: x, y: baseline - font.ascender))
    }

    private static func polyline(_ points: [NSPoint], width: CGFloat = 1.3) {
        guard let first = points.first else { return }
        let path = NSBezierPath()
        path.move(to: first)
        for p in points.dropFirst() { path.line(to: p) }
        path.lineWidth = width
        path.lineJoinStyle = .round
        path.lineCapStyle = .round
        path.stroke()
    }

    private enum Direction { case up, down, left, right }

    /// A filled triangular arrowhead whose point is at `tip`.
    private static func head(tip: NSPoint, direction: Direction, size: CGFloat = 2.4) {
        let length = size * 1.4
        let path = NSBezierPath()
        path.move(to: tip)
        switch direction {
        case .down:
            path.line(to: NSPoint(x: tip.x - size, y: tip.y - length))
            path.line(to: NSPoint(x: tip.x + size, y: tip.y - length))
        case .up:
            path.line(to: NSPoint(x: tip.x - size, y: tip.y + length))
            path.line(to: NSPoint(x: tip.x + size, y: tip.y + length))
        case .right:
            path.line(to: NSPoint(x: tip.x - length, y: tip.y - size))
            path.line(to: NSPoint(x: tip.x - length, y: tip.y + size))
        case .left:
            path.line(to: NSPoint(x: tip.x + length, y: tip.y - size))
            path.line(to: NSPoint(x: tip.x + length, y: tip.y + size))
        }
        path.close()
        path.fill()
    }
}
