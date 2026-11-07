import AppKit
import SwiftUI

/// Relief's visual identity.
///
/// - Lagoon #22D3C5, violet #7C5CFF and rose #FF5FA2 (gradient, from low to high frequencies).
/// - Night #12101F for dark backgrounds.
/// - Symbol: nested contour lines, like the relief of a map.
enum Brand {
    static let lagoon = Color(red: 0.133, green: 0.827, blue: 0.773)   // #22D3C5
    static let violet = Color(red: 0.486, green: 0.361, blue: 1.0)     // #7C5CFF
    static let rose = Color(red: 1.0, green: 0.373, blue: 0.635)       // #FF5FA2
    static let night = Color(red: 0.071, green: 0.063, blue: 0.122)    // #12101F

    static let gradient = LinearGradient(colors: [lagoon, violet, rose],
                                         startPoint: .leading, endPoint: .trailing)
    static let diagonal = LinearGradient(colors: [lagoon, violet, rose],
                                         startPoint: .bottomLeading, endPoint: .topTrailing)

    /// Menu bar icon: three nested arches, as a template image
    /// (macOS tints it black or white depending on the appearance).
    static func menuBarIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            NSColor.black.setStroke()
            let baseline: CGFloat = 3.5
            let centerX = rect.midX
            let arches: [(halfWidth: CGFloat, height: CGFloat)] = [(7, 11.5), (4.6, 7.6), (2.2, 3.8)]
            for arch in arches {
                let path = NSBezierPath()
                path.lineWidth = 1.6
                path.lineCapStyle = .round
                path.lineJoinStyle = .round
                let left = NSPoint(x: centerX - arch.halfWidth, y: baseline)
                let right = NSPoint(x: centerX + arch.halfWidth, y: baseline)
                let top = baseline + arch.height
                path.move(to: left)
                path.curve(to: NSPoint(x: centerX, y: top),
                           controlPoint1: NSPoint(x: left.x, y: baseline + arch.height * 0.62),
                           controlPoint2: NSPoint(x: centerX - arch.halfWidth * 0.55, y: top))
                path.curve(to: right,
                           controlPoint1: NSPoint(x: centerX + arch.halfWidth * 0.55, y: top),
                           controlPoint2: NSPoint(x: right.x, y: baseline + arch.height * 0.62))
                path.stroke()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// The contour mark used in the interface header.
struct ReliefMark: View {
    var size: CGFloat = 26

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(Brand.night)
            Image(nsImage: Brand.menuBarIcon())
                .renderingMode(.template)
                .resizable()
                .frame(width: size * 0.72, height: size * 0.72)
                .foregroundStyle(Brand.diagonal)
        }
        .frame(width: size, height: size)
    }
}
