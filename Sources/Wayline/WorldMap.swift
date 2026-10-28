import AppKit
import SwiftUI

struct GeoPoint: Equatable {
    var lat: Double
    var lon: Double

    func distance(to o: GeoPoint) -> Double {
        let r = Double.pi / 180
        let dLat = (o.lat - lat) * r, dLon = (o.lon - lon) * r
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat * r) * cos(o.lat * r) * sin(dLon / 2) * sin(dLon / 2)
        return 6371 * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}

extension GeoLocation {
    var point: GeoPoint { GeoPoint(lat: latitude, lon: longitude) }
    var place: String { !city.isEmpty ? city : (!region.isEmpty ? region : countryName) }
}

struct MapRegion: Equatable {
    var minLon: Double, maxLon: Double, minLat: Double, maxLat: Double

    static let europe = MapRegion(minLon: -8, maxLon: 46, minLat: 32, maxLat: 60)

    var midLat: Double { (minLat + maxLat) / 2 }
    var midLon: Double { (minLon + maxLon) / 2 }

    func lerp(to o: MapRegion, _ t: Double) -> MapRegion {
        func m(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
        return MapRegion(minLon: m(minLon, o.minLon), maxLon: m(maxLon, o.maxLon),
                         minLat: m(minLat, o.minLat), maxLat: m(maxLat, o.maxLat))
    }

    static func framing(_ points: [GeoPoint]) -> MapRegion {
        guard let first = points.first else { return .europe }
        var minLon = first.lon, maxLon = first.lon, minLat = first.lat, maxLat = first.lat
        for p in points.dropFirst() {
            minLon = min(minLon, p.lon); maxLon = max(maxLon, p.lon)
            minLat = min(minLat, p.lat); maxLat = max(maxLat, p.lat)
        }
        let spanLon = max((maxLon - minLon) * 1.25, 22), spanLat = max((maxLat - minLat) * 1.35, 13)
        let cLon = (minLon + maxLon) / 2, cLat = (minLat + maxLat) / 2
        var r = MapRegion(minLon: cLon - spanLon / 2, maxLon: cLon + spanLon / 2,
                          minLat: cLat - spanLat / 2, maxLat: cLat + spanLat / 2)
        if r.maxLat > 82 { r.minLat -= r.maxLat - 82; r.maxLat = 82 }
        if r.minLat < -56 { r.maxLat += -56 - r.minLat; r.minLat = -56 }
        return r
    }
}

struct MapProjection {
    let k: Double
    let c: Double
    let center: GeoPoint
    let origin: CGPoint

    init(region: MapRegion, focus: CGRect) {
        c = cos(region.midLat * .pi / 180)
        k = min(Double(focus.width) / ((region.maxLon - region.minLon) * c),
                Double(focus.height) / (region.maxLat - region.minLat))
        center = GeoPoint(lat: region.midLat, lon: region.midLon)
        origin = CGPoint(x: focus.midX, y: focus.midY)
    }

    func point(_ g: GeoPoint) -> CGPoint {
        CGPoint(x: origin.x + (g.lon - center.lon) * k * c, y: origin.y - (g.lat - center.lat) * k)
    }

    func geo(_ p: CGPoint) -> GeoPoint {
        GeoPoint(lat: center.lat - Double(p.y - origin.y) / k, lon: center.lon + Double(p.x - origin.x) / (k * c))
    }
}

enum WorldMask {
    static let bits: [UInt8] = Array(Data(base64Encoded: WorldMapData.mask, options: .ignoreUnknownCharacters) ?? Data())

    static func isLand(row: Int, column: Int) -> Bool {
        let i = row * WorldMapData.columns + column
        guard i >= 0, i >> 3 < bits.count else { return false }
        return (bits[i >> 3] >> (7 - UInt8(i & 7))) & 1 == 1
    }
}

private struct DotLayer: View, Equatable {
    let region: MapRegion
    let insets: EdgeInsets
    let glows: [Glow]
    let minSpacing: CGFloat

    struct Glow: Equatable {
        var at: GeoPoint
        var color: Color
        var radius: CGFloat
        var strength: Double
    }

    var body: some View {
        Canvas { ctx, size in
            let focus = focusRect(size, insets)
            let proj = MapProjection(region: region, focus: focus)
            let spacing = Double(minSpacing)
            let radius = spacing * 0.29
            let step = WorldMapData.step
            let ox = Double(proj.origin.x) - proj.center.lon * proj.k * proj.c
            let oy = Double(proj.origin.y) + proj.center.lat * proj.k
            let i0 = Int(((-ox) / spacing).rounded(.down)), i1 = Int(((Double(size.width) - ox) / spacing).rounded(.up))
            let j0 = Int(((-oy) / spacing).rounded(.down)), j1 = Int(((Double(size.height) - oy) / spacing).rounded(.up))
            guard i0 <= i1, j0 <= j1 else { return }

            var dots = Path()
            for j in j0...j1 {
                let y = oy + Double(j) * spacing
                let lat = (oy - y) / proj.k
                let row = Int(((WorldMapData.latTop - lat) / step).rounded(.down))
                guard row >= 0, row < WorldMapData.rows else { continue }
                for i in i0...i1 {
                    let x = ox + Double(i) * spacing
                    let lon = (x - ox) / (proj.k * proj.c)
                    guard lon >= -180, lon < 180 else { continue }
                    let col = Int(((lon + 180) / step).rounded(.down))
                    guard WorldMask.isLand(row: row, column: col) else { continue }
                    dots.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                }
            }
            ctx.fill(dots, with: .color(Theme.land))

            ctx.clip(to: dots)
            for g in glows {
                let p = proj.point(g.at)
                let rect = CGRect(x: p.x - g.radius, y: p.y - g.radius, width: g.radius * 2, height: g.radius * 2)
                ctx.fill(Path(ellipseIn: rect), with: .radialGradient(
                    Gradient(colors: [g.color.opacity(g.strength), g.color.opacity(0)]),
                    center: p, startRadius: 0, endRadius: g.radius))
            }
        }
    }
}

private func focusRect(_ size: CGSize, _ i: EdgeInsets) -> CGRect {
    CGRect(x: i.leading, y: i.top,
           width: max(size.width - i.leading - i.trailing, 40),
           height: max(size.height - i.top - i.bottom, 40))
}

struct RouteMap: View {
    var home: GeoLocation?
    var server: GeoLocation?
    var status: TunnelStore.Status
    var insets = EdgeInsets(top: 40, leading: 40, bottom: 40, trailing: 40)
    var showsLabels = true
    var homeCaption = L("Konumun", "You")
    var serverCaption = L("Sunucu", "Server")
    var minDotSpacing: CGFloat = 6
    var throughput: Double = 0

    @State private var move: (from: MapRegion, to: MapRegion, start: Date)?
    @State private var settleTick = 0
    @Environment(\.windowVisible) private var windowVisible
    @State private var connectedAt: Date?
    @State private var density = Smoothed(0.2)

    private static let moveDuration: TimeInterval = 1.8

    private var target: MapRegion {
        MapRegion.framing([home?.point, server?.point].compactMap { $0 })
    }

    private func region(at date: Date) -> MapRegion {
        guard let move else { return target }
        let elapsed = max(date.timeIntervalSince(move.start), Date().timeIntervalSince(move.start))
        let t = min(max(elapsed / Self.moveDuration, 0), 1)
        let eased = t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
        return move.from.lerp(to: move.to, eased)
    }

    private var animates: Bool { status != .disconnected }

    private var moving: Bool {
        guard let move else { return false }
        return Date().timeIntervalSince(move.start) < Self.moveDuration
    }

    var body: some View {
        let _ = settleTick
        ZStack {
            Motion(active: windowVisible && moving) { timeline in
                DotLayer(region: region(at: timeline.date), insets: insets, glows: glows, minSpacing: minDotSpacing)
                    .equatable()
            }
            Motion(active: windowVisible && (animates || moving)) { timeline in
                let now = timeline.date
                Canvas { ctx, size in
                    draw(&ctx, size: size, region: region(at: now), time: now.timeIntervalSinceReferenceDate)
                }
            }
            if showsLabels {
                Motion(active: windowVisible && moving) { timeline in
                    LabelLayer(region: region(at: timeline.date), insets: insets, labels: labels)
                        .equatable()
                }
            }
        }
        .onChange(of: target) { old, new in
            let now = Date()
            let from = move.map { _ in region(at: now) } ?? old
            move = (from, new, now)
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.moveDuration + 0.1) { settleTick += 1 }
        }
        .onChange(of: status) { old, new in
            if new == .connected, old != .connected { connectedAt = Date() }
            if new != .connected { connectedAt = nil }
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        switch (home, server) {
        case let (h?, s?): "\(L("Rota", "Route")): \(h.place), \(h.countryName) → \(s.place), \(s.countryName)"
        case let (nil, s?): "\(L("Sunucu", "Server")): \(s.place), \(s.countryName)"
        default: L("Dünya haritası", "World map")
        }
    }

    private var glows: [DotLayer.Glow] {
        var list: [DotLayer.Glow] = []
        if let home { list.append(.init(at: home.point, color: Theme.sky, radius: 70, strength: 0.35)) }
        if let server {
            let connected = status == .connected
            list.append(.init(at: server.point, color: connected ? Theme.mint : status.color,
                              radius: connected ? 110 : 70, strength: connected ? 0.55 : 0.25))
        }
        return list
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, region: MapRegion, time: Double) {
        let proj = MapProjection(region: region, focus: focusRect(size, insets))
        let homeP = home.map { proj.point($0.point) }
        let serverP = server.map { proj.point($0.point) }

        if let a = homeP, let b = serverP, hypot(b.x - a.x, b.y - a.y) > 6 {
            let arc = Arc(from: a, to: b)
            drawArc(&ctx, arc, time: time)
        }
        if let a = homeP { drawHome(&ctx, at: a) }
        if let b = serverP { drawServer(&ctx, at: b, time: time) }
    }

    private var labels: [LabelLayer.Label] {
        var list: [LabelLayer.Label] = []
        if let home {
            list.append(.init(at: home.point, title: "\(home.flag) \(home.place)",
                              detail: "\(homeCaption)  \(home.ip)", accent: Theme.sky))
        }
        if let server {
            list.append(.init(at: server.point, title: "\(server.flag) \(server.place)",
                              detail: "\(serverCaption)  \(server.ip)", accent: status == .connected ? Theme.mint : Theme.muted))
        }
        return list
    }

    private func drawArc(_ ctx: inout GraphicsContext, _ arc: Arc, time: Double) {
        let full = arc.path(0, 1)
        switch status {
        case .connected:
            let gradient = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [Theme.sky, Theme.mint]), startPoint: arc.p0, endPoint: arc.p1)
            ctx.stroke(full, with: .linearGradient(Gradient(colors: [Theme.sky.opacity(0.12), Theme.mint.opacity(0.16)]),
                                                   startPoint: arc.p0, endPoint: arc.p1),
                       style: StrokeStyle(lineWidth: 7, lineCap: .round))
            ctx.opacity = 0.75
            ctx.stroke(full, with: gradient, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            ctx.opacity = 1
            let target = 0.12 + 0.88 * min(max(log10(1 + throughput / 2048) / 3.2, 0), 1)
            let d = density.step(to: target, at: time)
            let slots = [0, 4, 2, 6, 1, 5, 3, 7]
            let visible = 2 + d * Double(slots.count - 2)
            let period = 3.4
            for (rank, slot) in slots.enumerated() {
                let presence = min(max(visible - Double(rank), 0), 1)
                guard presence > 0.01 else { continue }
                let phase = (time / period + Double(slot) / Double(slots.count)).truncatingRemainder(dividingBy: 1)
                let fade = sin(phase * .pi) * presence
                for j in 0..<14 {
                    let t = phase - Double(j) * 0.010
                    guard t > 0 else { break }
                    let p = arc.point(t)
                    let r = 2.2 - Double(j) * 0.11
                    let a = fade * (1 - Double(j) / 14) * 0.85
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                             with: .color(Color.white.opacity(a * 0.55)))
                }
                let head = arc.point(phase)
                ctx.fill(Path(ellipseIn: CGRect(x: head.x - 12, y: head.y - 12, width: 24, height: 24)),
                         with: .radialGradient(Gradient(colors: [Theme.mint.opacity(0.42 * fade), Theme.mint.opacity(0)]),
                                               center: head, startRadius: 0, endRadius: 12))
            }

        case .connecting, .reconnecting:
            ctx.stroke(full, with: .color(Theme.amber.opacity(0.18)),
                       style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [2, 5]))
            let cycle = 2.8
            let local = time.truncatingRemainder(dividingBy: cycle)
            let t = min(local / 2.2, 1)
            let progress = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
            let alpha = local > 2.2 ? max(0, 1 - (local - 2.2) / 0.6) : 1
            let sweep = 0.5 - 0.5 * cos(time * 2 * .pi / 3.2)
            let lo = max(sweep - 0.07, 0), hi = min(sweep + 0.07, 1)
            if hi - lo > 0.01 {
                ctx.stroke(arc.path(lo, hi), with: .linearGradient(
                    Gradient(colors: [Theme.amber.opacity(0), Theme.amber.opacity(0.32), Theme.amber.opacity(0)]),
                    startPoint: arc.point(lo), endPoint: arc.point(hi)),
                           style: StrokeStyle(lineWidth: 5, lineCap: .round))
            }
            guard progress > 0.01 else { return }
            ctx.stroke(arc.path(0, progress), with: .linearGradient(
                Gradient(colors: [Theme.amber.opacity(0.15 * alpha), Theme.amber.opacity(0.9 * alpha)]),
                startPoint: arc.p0, endPoint: arc.point(progress)),
                       style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            let head = arc.point(progress)
            ctx.fill(Path(ellipseIn: CGRect(x: head.x - 10, y: head.y - 10, width: 20, height: 20)),
                     with: .radialGradient(Gradient(colors: [Theme.amber.opacity(0.5 * alpha), Theme.amber.opacity(0)]),
                                           center: head, startRadius: 0, endRadius: 10))

        case .disconnected, .disconnecting:
            ctx.stroke(full, with: .color(Theme.slate.opacity(0.38)),
                       style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [2, 5]))
        }
    }

    private func drawHome(_ ctx: inout GraphicsContext, at p: CGPoint) {
        ring(&ctx, p, radius: 8, color: Theme.sky.opacity(0.45), width: 1)
        disc(&ctx, p, radius: 3.6, color: Theme.sky)
    }

    private func drawServer(_ ctx: inout GraphicsContext, at p: CGPoint, time: Double) {
        switch status {
        case .connected:
            let breath = 0.5 + 0.5 * sin(time * 2 * .pi / 3.6)
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - 30, y: p.y - 30, width: 60, height: 60)),
                     with: .radialGradient(Gradient(colors: [Theme.mint.opacity(0.18 + 0.20 * breath), Theme.mint.opacity(0)]),
                                           center: p, startRadius: 0, endRadius: 30))
            ring(&ctx, p, radius: 9, color: Theme.mint.opacity(0.55 + 0.25 * breath), width: 1.2)
            disc(&ctx, p, radius: 4.2, color: Theme.mint)
            if let connectedAt {
                let e = Date(timeIntervalSinceReferenceDate: time).timeIntervalSince(connectedAt)
                for k in 0..<3 {
                    let local = (e - Double(k) * 0.45) / 2.2
                    guard local > 0, local < 1 else { continue }
                    let eased = 1 - pow(1 - local, 2)
                    ring(&ctx, p, radius: 10 + 70 * eased, color: Theme.mint.opacity(0.5 * pow(1 - local, 1.6)), width: 1.2)
                }
            }
        case .connecting, .reconnecting:
            let breath = 0.5 + 0.5 * sin(time * 2 * .pi / 2.4)
            ring(&ctx, p, radius: 9, color: Theme.amber.opacity(0.3 + 0.4 * breath), width: 1.2)
            disc(&ctx, p, radius: 3.8, color: Theme.amber.opacity(0.85))
            let sonar = time.truncatingRemainder(dividingBy: 2.4) / 2.4
            ring(&ctx, p, radius: 10 + 30 * sonar, color: Theme.amber.opacity(0.32 * pow(1 - sonar, 2)), width: 1)
        case .disconnected, .disconnecting:
            ring(&ctx, p, radius: 8, color: Theme.slate.opacity(0.5), width: 1)
            ring(&ctx, p, radius: 3.4, color: Theme.slate, width: 1.4)
        }
    }

    private func disc(_ ctx: inout GraphicsContext, _ p: CGPoint, radius r: CGFloat, color: Color) {
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(color))
    }

    private func ring(_ ctx: inout GraphicsContext, _ p: CGPoint, radius r: CGFloat, color: Color, width: CGFloat) {
        ctx.stroke(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(color), lineWidth: width)
    }
}

private struct LabelLayer: View, Equatable {
    struct Label: Equatable {
        var at: GeoPoint
        var title: String
        var detail: String
        var accent: Color
    }

    let region: MapRegion
    let insets: EdgeInsets
    let labels: [Label]

    var body: some View {
        Canvas { ctx, size in
            let proj = MapProjection(region: region, focus: focusRect(size, insets))
            let points = labels.map { proj.point($0.at) }
            for (i, label) in labels.enumerated() {
                let p = points[i]
                let other = points.indices.first { $0 != i }.map { points[$0] }
                let above = other.map { i == 0 ? p.y < $0.y - 4 : p.y <= $0.y + 4 } ?? true
                draw(&ctx, size: size, at: p, above: above, label: label)
            }
        }
        .allowsHitTesting(false)
    }

    private func draw(_ ctx: inout GraphicsContext, size: CGSize, at p: CGPoint, above: Bool, label: Label) {
        let titleText = ctx.resolve(Text(label.title).font(.system(size: 12, weight: .semibold)).foregroundColor(Theme.text))
        let detailText = ctx.resolve(Text(label.detail).font(.system(size: 10.5, weight: .medium).monospacedDigit())
            .foregroundColor(label.accent))
        let ts = titleText.measure(in: CGSize(width: 260, height: 40))
        let ds = detailText.measure(in: CGSize(width: 260, height: 40))
        let w = max(ts.width, ds.width) + 20, h = ts.height + ds.height + 12
        var x = p.x - w / 2
        var y = above ? p.y - 16 - h : p.y + 16
        x = min(max(x, 8), size.width - w - 8)
        y = min(max(y, 8), size.height - h - 8)
        let rect = CGRect(x: x, y: y, width: w, height: h)
        let shape = Path(roundedRect: rect, cornerRadius: 8, style: .continuous)
        ctx.fill(shape, with: .color(Theme.background.opacity(0.78)))
        ctx.stroke(shape, with: .color(Theme.strokeStrong), lineWidth: 1)
        ctx.draw(titleText, at: CGPoint(x: x + 10, y: y + 6), anchor: .topLeading)
        ctx.draw(detailText, at: CGPoint(x: x + 10, y: y + 6 + ts.height + 1), anchor: .topLeading)
    }
}

private struct Arc {
    let p0: CGPoint, p1: CGPoint, control: CGPoint

    init(from a: CGPoint, to b: CGPoint) {
        p0 = a; p1 = b
        let dx = b.x - a.x, dy = b.y - a.y
        let d = max(hypot(dx, dy), 1)
        var n = CGPoint(x: -dy / d, y: dx / d)
        if n.y > 0 { n = CGPoint(x: -n.x, y: -n.y) }
        let lift = min(d * 0.26, 120)
        control = CGPoint(x: (a.x + b.x) / 2 + n.x * lift, y: (a.y + b.y) / 2 + n.y * lift)
    }

    func point(_ t: Double) -> CGPoint {
        let u = 1 - t
        return CGPoint(x: u * u * p0.x + 2 * u * t * control.x + t * t * p1.x,
                       y: u * u * p0.y + 2 * u * t * control.y + t * t * p1.y)
    }

    func path(_ from: Double, _ to: Double) -> Path {
        var path = Path()
        let steps = 48
        for i in 0...steps {
            let t = from + (to - from) * Double(i) / Double(steps)
            i == 0 ? path.move(to: point(t)) : path.addLine(to: point(t))
        }
        return path
    }
}
