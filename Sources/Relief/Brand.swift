import AppKit
import SwiftUI

/// Relief's visual identity. The interface uses the system accent color like every Mac app;
/// the brand colors only appear in the icon and the equalizer curve.
enum Brand {
    static let lagoon = Color(red: 0.133, green: 0.827, blue: 0.773)   // #22D3C5
    static let violet = Color(red: 0.486, green: 0.361, blue: 1.0)     // #7C5CFF
    static let rose = Color(red: 1.0, green: 0.373, blue: 0.635)       // #FF5FA2

    /// Menu bar icon (template image, tinted by macOS): two sound ridges in relief,
    /// an outlined one behind a filled one — the app icon's landscape, simplified.
    static func menuBarIcon() -> NSImage {
        func ridge(base: CGFloat, peaks: [(x: CGFloat, height: CGFloat, width: CGFloat)]) -> [NSPoint] {
            (0...90).map { i in
                let x = 1.2 + 15.6 * CGFloat(i) / 90
                var y = base
                for p in peaks { y -= p.height * exp(-pow((x - p.x) / p.width, 2)) }
                return NSPoint(x: x, y: y)
            }
        }
        let back = ridge(base: 14.6, peaks: [(11.4, 11.2, 1.75), (15.2, 2.0, 1.2)])
        let front = ridge(base: 15.6, peaks: [(6.4, 9.4, 1.65), (2.6, 1.6, 1.2), (10.6, 1.8, 1.1)])

        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            guard let context = NSGraphicsContext.current else { return false }
            let line = NSBezierPath()
            line.move(to: back[0])
            for p in back.dropFirst() { line.line(to: p) }
            line.lineWidth = 1.5
            line.lineJoinStyle = .round
            line.lineCapStyle = .round

            let area = NSBezierPath()
            area.move(to: front[0])
            for p in front.dropFirst() { area.line(to: p) }
            area.line(to: NSPoint(x: front[front.count - 1].x, y: 16))
            area.line(to: NSPoint(x: front[0].x, y: 16))
            area.close()
            area.lineJoinStyle = .round

            NSColor.black.setStroke()
            line.stroke()
            // A gap around the front ridge, so the two read as separate layers.
            context.saveGraphicsState()
            context.compositingOperation = .clear
            area.lineWidth = 2.8
            area.stroke()
            area.fill()
            context.restoreGraphicsState()
            NSColor.black.setFill()
            NSColor.black.setStroke()
            area.lineWidth = 0.6
            area.fill()
            area.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Relief"
        return image
    }
}

/// The app icon, as shown by macOS (used in the panel header and the settings).
struct AppIconView: View {
    var size: CGFloat = 28

    var body: some View {
        Image(nsImage: NSApp.applicationIconImage ?? NSImage())
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}
