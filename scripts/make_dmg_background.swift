import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let scale = CGFloat(Double(CommandLine.arguments[2]) ?? 1)
let size = NSSize(width: 640, height: 400)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = size
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let bounds = NSRect(origin: .zero, size: size)
NSGradient(colors: [NSColor(red: 0.055, green: 0.07, blue: 0.095, alpha: 1),
                    NSColor(red: 0.03, green: 0.04, blue: 0.055, alpha: 1)])!.draw(in: bounds, angle: -90)

NSColor(white: 1, alpha: 0.05).setFill()
for x in stride(from: 12.0, to: size.width, by: 16) {
    for y in stride(from: 12.0, to: size.height, by: 16) {
        NSBezierPath(ovalIn: NSRect(x: x, y: y, width: 1.6, height: 1.6)).fill()
    }
}

let mint = NSColor(red: 0.36, green: 0.89, blue: 0.70, alpha: 1)
let arc = NSBezierPath()
arc.move(to: NSPoint(x: 250, y: 215))
arc.curve(to: NSPoint(x: 390, y: 215), controlPoint1: NSPoint(x: 290, y: 255), controlPoint2: NSPoint(x: 350, y: 255))
arc.lineWidth = 2.5
arc.lineCapStyle = .round
let dash: [CGFloat] = [2, 7]
arc.setLineDash(dash, count: 2, phase: 0)
mint.withAlphaComponent(0.85).setStroke()
arc.stroke()
let head = NSBezierPath()
head.move(to: NSPoint(x: 380, y: 226))
head.line(to: NSPoint(x: 392, y: 214))
head.line(to: NSPoint(x: 377, y: 208))
head.lineWidth = 2.5
head.lineCapStyle = .round
head.lineJoinStyle = .round
mint.setStroke()
head.stroke()

func draw(_ text: String, y: CGFloat, size fontSize: CGFloat, color: NSColor, weight: NSFont.Weight) {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: fontSize, weight: weight),
                                                .foregroundColor: color, .paragraphStyle: style]
    (text as NSString).draw(in: NSRect(x: 0, y: y, width: size.width, height: fontSize * 1.5), withAttributes: attrs)
}
draw("Wayline'ı Applications klasörüne sürükle", y: 82, size: 15, color: NSColor(white: 0.93, alpha: 1), weight: .semibold)
draw("Drag Wayline into the Applications folder", y: 60, size: 12, color: NSColor(white: 0.55, alpha: 1), weight: .regular)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: output)
