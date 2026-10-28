import AppKit
import SwiftUI

enum Theme {
    static let background = Color(red: 0.035, green: 0.047, blue: 0.063)
    static let sidebar = Color(red: 0.047, green: 0.059, blue: 0.078)
    static let sea = Color(red: 0.039, green: 0.055, blue: 0.075)
    static let panel = Color(red: 0.063, green: 0.078, blue: 0.102)
    static let panelRaised = Color(red: 0.090, green: 0.106, blue: 0.137)
    static let stroke = Color.white.opacity(0.065)
    static let strokeStrong = Color.white.opacity(0.11)

    static let text = Color(red: 0.93, green: 0.95, blue: 0.97)
    static let muted = Color(red: 0.55, green: 0.59, blue: 0.65)
    static let faint = Color(red: 0.33, green: 0.37, blue: 0.43)

    static let land = Color(red: 0.21, green: 0.27, blue: 0.34)

    static let mint = Color(red: 0.36, green: 0.89, blue: 0.70)
    static let amber = Color(red: 0.95, green: 0.71, blue: 0.35)
    static let slate = Color(red: 0.50, green: 0.55, blue: 0.62)
    static let rose = Color(red: 0.94, green: 0.44, blue: 0.47)
    static let sky = Color(red: 0.48, green: 0.66, blue: 1.00)

    static func display(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

extension TunnelStore.Status {
    var color: Color {
        switch self {
        case .connected: Theme.mint
        case .connecting, .reconnecting: Theme.amber
        case .disconnecting, .disconnected: Theme.slate
        }
    }
}

extension TunnelStore.Event.Kind {
    var color: Color {
        switch self {
        case .info: Theme.sky
        case .success: Theme.mint
        case .warning: Theme.amber
        case .error: Theme.rose
        }
    }
}

struct Card<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.stroke))
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(Theme.muted)
    }
}

struct WaylineMark: View {
    var color: Color = Theme.mint
    var size: CGFloat = 22

    var body: some View {
        Canvas { ctx, s in
            let w = s.width
            let line = WaylineMark.route(in: CGRect(origin: .zero, size: s))
            let a = WaylineMark.start(in: s), b = WaylineMark.end(in: s)
            ctx.stroke(line, with: .linearGradient(Gradient(colors: [Theme.sky.opacity(0.85), color]),
                                                   startPoint: a, endPoint: b),
                       style: StrokeStyle(lineWidth: max(w * 0.085, 1.4), lineCap: .round))
            let r0 = w * 0.085
            ctx.fill(Path(ellipseIn: CGRect(x: a.x - r0, y: a.y - r0, width: r0 * 2, height: r0 * 2)), with: .color(Theme.sky))
            let r1 = w * 0.1
            ctx.fill(Path(ellipseIn: CGRect(x: b.x - r1, y: b.y - r1, width: r1 * 2, height: r1 * 2)), with: .color(color))
            let r2 = w * 0.19
            ctx.stroke(Path(ellipseIn: CGRect(x: b.x - r2, y: b.y - r2, width: r2 * 2, height: r2 * 2)),
                       with: .color(color.opacity(0.4)), lineWidth: max(w * 0.045, 1))
        }
        .frame(width: size, height: size)
    }

    static func start(in s: CGSize) -> CGPoint { CGPoint(x: s.width * 0.15, y: s.height * 0.7) }
    static func end(in s: CGSize) -> CGPoint { CGPoint(x: s.width * 0.77, y: s.height * 0.55) }

    static func route(in r: CGRect) -> Path {
        let a = start(in: r.size), b = end(in: r.size)
        var p = Path()
        p.move(to: CGPoint(x: r.minX + a.x, y: r.minY + a.y))
        p.addQuadCurve(to: CGPoint(x: r.minX + b.x, y: r.minY + b.y),
                       control: CGPoint(x: r.minX + r.width * 0.4, y: r.minY - r.height * 0.08))
        return p
    }

    private static let menuBarImages = [
        drawMenuBarImage(connected: true, transitioning: false),
        drawMenuBarImage(connected: false, transitioning: true),
        drawMenuBarImage(connected: false, transitioning: false),
    ]

    static func menuBarImage(connected: Bool, transitioning: Bool) -> NSImage {
        menuBarImages[connected ? 0 : transitioning ? 1 : 2]
    }

    private static func drawMenuBarImage(connected: Bool, transitioning: Bool) -> NSImage {
        let side: CGFloat = 18
        let image = NSImage(size: NSSize(width: side, height: side), flipped: true) { rect in
            guard let cg = NSGraphicsContext.current?.cgContext else { return false }
            let s = rect.size
            let a = start(in: s), b = end(in: s)
            cg.setStrokeColor(NSColor.black.cgColor)
            cg.setFillColor(NSColor.black.cgColor)
            cg.setLineCap(.round)
            cg.setLineWidth(1.6)
            if !connected { cg.setLineDash(phase: 0, lengths: transitioning ? [3, 2] : [1.2, 2.6]) }
            cg.addPath(route(in: rect).cgPath)
            cg.strokePath()
            cg.setLineDash(phase: 0, lengths: [])
            cg.fillEllipse(in: CGRect(x: a.x - 1.9, y: a.y - 1.9, width: 3.8, height: 3.8))
            let r: CGFloat = 2.6
            let dot = CGRect(x: b.x - r, y: b.y - r, width: r * 2, height: r * 2)
            if connected {
                cg.fillEllipse(in: dot)
            } else {
                cg.setLineWidth(1.4)
                cg.strokeEllipse(in: dot.insetBy(dx: 0.3, dy: 0.3))
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
