import AppKit
import SwiftUI

/// Relief's visual identity. The interface uses the system accent color like every Mac app;
/// the brand colors only appear in the icon and the equalizer curve.
enum Brand {
    static let lagoon = Color(red: 0.133, green: 0.827, blue: 0.773)   // #22D3C5
    static let violet = Color(red: 0.486, green: 0.361, blue: 1.0)     // #7C5CFF
    static let rose = Color(red: 1.0, green: 0.373, blue: 0.635)       // #FF5FA2

    /// Menu bar icon (template image): a sound wave, with a lighter offset copy for the relief.
    static func menuBarIcon() -> NSImage {
        func wave(dy: CGFloat) -> NSBezierPath {
            let path = NSBezierPath()
            for i in 0...120 {
                let t = CGFloat(i) / 120
                let envelope = pow(sin(.pi * t), 1.2)
                let point = NSPoint(x: 1.8 + 14.4 * t, y: 9 + dy - envelope * 5.6 * sin(2 * .pi * 2.2 * t))
                i == 0 ? path.move(to: point) : path.line(to: point)
            }
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            return path
        }
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let shadow = wave(dy: 1.9)
            shadow.lineWidth = 1.7
            NSColor.black.withAlphaComponent(0.45).setStroke()
            shadow.stroke()
            let main = wave(dy: 0)
            main.lineWidth = 1.9
            NSColor.black.setStroke()
            main.stroke()
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
