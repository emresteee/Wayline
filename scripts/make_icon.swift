import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let mint = CGColor(red: 0.36, green: 0.89, blue: 0.70, alpha: 1)
let sky = CGColor(red: 0.48, green: 0.66, blue: 1.00, alpha: 1)

func color(_ c: CGColor, _ a: CGFloat) -> CGColor { c.copy(alpha: a)! }

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let cg = NSGraphicsContext.current!.cgContext
    let s = CGFloat(px)
    cg.translateBy(x: 0, y: s)
    cg.scaleBy(x: 1, y: -1)

    let inset = s * 0.1
    let tile = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let w = tile.width
    let shape = CGPath(roundedRect: tile, cornerWidth: w * 0.225, cornerHeight: w * 0.225, transform: nil)
    let space = CGColorSpaceCreateDeviceRGB()

    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: s * 0.01), blur: s * 0.025, color: color(.black, 0.4))
    cg.addPath(shape)
    cg.setFillColor(.black)
    cg.fillPath()
    cg.restoreGState()

    cg.saveGState()
    cg.addPath(shape)
    cg.clip()

    let base = CGGradient(colorsSpace: space, colors: [CGColor(red: 0.075, green: 0.10, blue: 0.13, alpha: 1),
                                                        CGColor(red: 0.03, green: 0.04, blue: 0.055, alpha: 1)] as CFArray,
                          locations: [0, 1])!
    cg.drawLinearGradient(base, start: CGPoint(x: 0, y: tile.minY), end: CGPoint(x: 0, y: tile.maxY), options: [])

    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: tile.minX + w * x, y: tile.minY + w * y) }
    let a = p(0.2, 0.68), b = p(0.76, 0.54), c = p(0.42, 0.02)

    let glow = CGGradient(colorsSpace: space, colors: [color(mint, 0.30), color(mint, 0)] as CFArray, locations: [0, 1])!
    cg.drawRadialGradient(glow, startCenter: b, startRadius: 0, endCenter: b, endRadius: w * 0.5, options: [])

    if px >= 64 {
        let step = w / 15
        let r = step * 0.17
        var y = tile.minY + step * 0.5
        while y < tile.maxY {
            var x = tile.minX + step * 0.5
            while x < tile.maxX {
                let ny = (y - tile.minY) / w, nx = (x - tile.minX) / w
                let coast = 0.5 + 0.08 * sin(nx * 9) + 0.05 * cos(nx * 17 + 1)
                if ny > coast {
                    let fade = min((ny - coast) * 3.5, 1) * 0.16
                    cg.setFillColor(CGColor(red: 0.45, green: 0.55, blue: 0.68, alpha: fade))
                    cg.fillEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
                }
                x += step
            }
            y += step
        }
    }

    let route = CGMutablePath()
    route.move(to: a)
    route.addQuadCurve(to: b, control: c)

    cg.saveGState()
    cg.addPath(route)
    cg.setLineWidth(w * 0.13)
    cg.setLineCap(.round)
    cg.replacePathWithStrokedPath()
    cg.clip()
    let haze = CGGradient(colorsSpace: space, colors: [color(sky, 0.12), color(mint, 0.18)] as CFArray, locations: [0, 1])!
    cg.drawLinearGradient(haze, start: a, end: b, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    cg.restoreGState()

    cg.saveGState()
    cg.addPath(route)
    cg.setLineWidth(w * 0.058)
    cg.setLineCap(.round)
    cg.replacePathWithStrokedPath()
    cg.clip()
    let line = CGGradient(colorsSpace: space, colors: [sky, mint] as CFArray, locations: [0, 1])!
    cg.drawLinearGradient(line, start: a, end: b, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    cg.restoreGState()

    func onArc(_ t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(x: u * u * a.x + 2 * u * t * c.x + t * t * b.x, y: u * u * a.y + 2 * u * t * c.y + t * t * b.y)
    }
    if px >= 64 {
        let spark = onArc(0.58)
        let sparkGlow = CGGradient(colorsSpace: space, colors: [CGColor(red: 1, green: 1, blue: 1, alpha: 0.75),
                                                                 color(mint, 0)] as CFArray, locations: [0, 1])!
        cg.drawRadialGradient(sparkGlow, startCenter: spark, startRadius: 0, endCenter: spark, endRadius: w * 0.05, options: [])
    }

    let r0 = w * 0.055
    cg.setFillColor(sky)
    cg.fillEllipse(in: CGRect(x: a.x - r0, y: a.y - r0, width: r0 * 2, height: r0 * 2))

    let r1 = w * 0.07
    cg.setFillColor(mint)
    cg.fillEllipse(in: CGRect(x: b.x - r1, y: b.y - r1, width: r1 * 2, height: r1 * 2))
    let r2 = w * 0.13
    cg.setStrokeColor(color(mint, 0.45))
    cg.setLineWidth(w * 0.022)
    cg.strokeEllipse(in: CGRect(x: b.x - r2, y: b.y - r2, width: r2 * 2, height: r2 * 2))

    cg.restoreGState()

    cg.addPath(CGPath(roundedRect: tile.insetBy(dx: s * 0.002, dy: s * 0.002), cornerWidth: w * 0.223, cornerHeight: w * 0.223, transform: nil))
    cg.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.07))
    cg.setLineWidth(max(s * 0.004, 0.5))
    cg.strokePath()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try render(size).write(to: output.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2).write(to: output.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
