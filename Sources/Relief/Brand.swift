import AppKit
import SwiftUI

/// Relief's visual identity. The interface uses the system accent color like every Mac app;
/// the brand colors only appear in the icon and the equalizer curve.
enum Brand {
    static let lagoon = Color(red: 0.133, green: 0.827, blue: 0.773)   // #22D3C5
    static let violet = Color(red: 0.486, green: 0.361, blue: 1.0)     // #7C5CFF
    static let rose = Color(red: 1.0, green: 0.373, blue: 0.635)       // #FF5FA2

    /// Menu bar icon (template image, tinted by macOS): a speaker and two waves,
    /// with a lighter offset copy of the waves for the relief.
    static func menuBarIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setFill()
            NSColor.black.setStroke()

            let speaker = NSBezierPath()
            speaker.move(to: NSPoint(x: 2.2, y: 6.6))
            speaker.line(to: NSPoint(x: 5, y: 6.6))
            speaker.line(to: NSPoint(x: 9, y: 3.4))
            speaker.line(to: NSPoint(x: 9, y: 14.6))
            speaker.line(to: NSPoint(x: 5, y: 11.4))
            speaker.line(to: NSPoint(x: 2.2, y: 11.4))
            speaker.close()
            speaker.lineWidth = 1
            speaker.lineJoinStyle = .round
            speaker.fill()
            speaker.stroke()

            func wave(radius: CGFloat, halfAngle: CGFloat, dy: CGFloat, alpha: CGFloat) {
                let path = NSBezierPath()
                // Flipped coordinates: angles go clockwise, so draw from −a to +a.
                path.appendArc(withCenter: NSPoint(x: 9.4, y: 9 + dy), radius: radius,
                               startAngle: -halfAngle, endAngle: halfAngle, clockwise: false)
                path.lineWidth = 1.5
                path.lineCapStyle = .round
                NSColor.black.withAlphaComponent(alpha).setStroke()
                path.stroke()
            }
            wave(radius: 3.2, halfAngle: 48, dy: 1.9, alpha: 0.45)
            wave(radius: 6.4, halfAngle: 50, dy: 1.9, alpha: 0.45)
            wave(radius: 3.2, halfAngle: 48, dy: 0, alpha: 1)
            wave(radius: 6.4, halfAngle: 50, dy: 0, alpha: 1)
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
