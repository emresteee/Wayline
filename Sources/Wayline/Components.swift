import SwiftUI

struct PowerButton: View {
    let status: TunnelStore.Status
    var diameter: CGFloat = 132
    let action: () -> Void

    @State private var hovering = false
    @Environment(\.windowVisible) private var windowVisible

    private var lit: Bool { status == .connected }

    var body: some View {
        Button(action: action) {
            ZStack {
                Motion(active: status.isTransitioning && windowVisible) { timeline in
                    let t = status.isTransitioning ? timeline.date.timeIntervalSinceReferenceDate : nil
                    Canvas { ctx, size in
                        let c = CGPoint(x: size.width / 2, y: size.height / 2)
                        let r = size.width / 2
                        let head = t.map { ($0 / 2.4).truncatingRemainder(dividingBy: 1) * 2 * .pi }
                        for i in 0..<72 {
                            let a = Double(i) / 72 * 2 * .pi
                            let long = i % 6 == 0
                            var p = Path()
                            p.move(to: CGPoint(x: c.x + cos(a) * (r - 1), y: c.y + sin(a) * (r - 1)))
                            p.addLine(to: CGPoint(x: c.x + cos(a) * (r - (long ? 7 : 4)), y: c.y + sin(a) * (r - (long ? 7 : 4))))
                            var base = long ? 0.16 : 0.07
                            var shine = 0.0
                            if let head {
                                var behind = (head - a).truncatingRemainder(dividingBy: 2 * .pi)
                                if behind < 0 { behind += 2 * .pi }
                                shine = exp(-behind * 1.6)
                                base *= 0.8
                            }
                            ctx.stroke(p, with: .color(.white.opacity(base)), lineWidth: 1)
                            if shine > 0.02 {
                                ctx.stroke(p, with: .color(status.color.opacity(0.75 * shine)), lineWidth: 1.2)
                            }
                        }
                    }
                }
                Circle()
                    .inset(by: 4)
                    .stroke(status.color.opacity(lit ? 0.55 : 0), lineWidth: 1)

                RadialGradient(colors: [status.color.opacity(lit ? 0.22 : 0.07), Theme.panel],
                               center: .init(x: 0.5, y: 0.35), startRadius: 0, endRadius: diameter * 0.45)
                    .clipShape(Circle())
                    .padding(14)
                Circle()
                    .inset(by: 14)
                    .strokeBorder(status.color.opacity(lit ? 0.75 : (hovering ? 0.45 : 0.22)), lineWidth: 1.5)

                if status.isTransitioning {
                    Motion(active: windowVisible) { timeline in
                        let t = timeline.date.timeIntervalSinceReferenceDate
                        Circle()
                            .inset(by: 14)
                            .trim(from: 0, to: 0.22)
                            .stroke(AngularGradient(colors: [status.color.opacity(0), status.color],
                                                    center: .center, startAngle: .degrees(0), endAngle: .degrees(80)),
                                    style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(t.truncatingRemainder(dividingBy: 2.4) / 2.4 * 360))
                    }
                    .transition(.opacity)
                }

                VStack(spacing: 7) {
                    Image(systemName: "power")
                        .font(.system(size: diameter * 0.2, weight: .medium))
                    Text(label)
                        .font(.system(size: 10.5, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(width: diameter - 36, height: 14)
                }
                .foregroundStyle(lit ? status.color : (status == .disconnected ? Theme.text.opacity(hovering ? 1 : 0.8) : status.color))
            }
            .frame(width: diameter, height: diameter)
            .shadow(color: status.color.opacity(lit ? 0.32 : 0), radius: 26)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .animation(.easeInOut(duration: 0.6), value: status)
        .animation(.easeInOut(duration: 0.25), value: hovering)
        .disabled(status == .disconnecting)
        .help(status == .connected ? L("Bağlantıyı kes", "Disconnect") : L("Bağlan", "Connect"))
    }

    private var label: String {
        switch status {
        case .disconnected: L("Bağlan", "Connect")
        case .connected: L("Bağlantıyı kes", "Disconnect")
        case .disconnecting: L("Kesiliyor", "Disconnecting")
        default: L("Vazgeç", "Cancel")
        }
    }
}

struct LiveValue: View {
    let text: String
    var color: Color = Theme.text
    var size: CGFloat = 22
    var width: CGFloat? = nil
    var glows = true
    var glowColor: Color = Theme.mint

    var body: some View {
        Text(text)
            .font(Theme.display(size))
            .monospacedDigit()
            .foregroundStyle(color)
            .lineLimit(1)
            .frame(width: width, alignment: .leading)
            .contentTransition(.identity)
            .valueGlow(glows ? text : "", color: glowColor)
            .animation(.easeInOut(duration: 0.5), value: color)
    }
}

struct ThroughputChart: View {
    let samples: [TunnelStore.Sample]
    var active = true

    var body: some View {
        Canvas { ctx, size in
            let peak = max(samples.map { max($0.rx, $0.tx) }.max() ?? 0, 16 * 1024) * 1.08
            let step = size.width / CGFloat(max(samples.count - 1, 1))

            for i in 0...3 {
                let y = size.height * CGFloat(i) / 3
                var grid = Path()
                grid.move(to: CGPoint(x: 0, y: min(max(y, 0.5), size.height - 0.5)))
                grid.addLine(to: CGPoint(x: size.width, y: min(max(y, 0.5), size.height - 0.5)))
                ctx.stroke(grid, with: .color(.white.opacity(i == 3 ? 0.08 : 0.035)),
                           style: StrokeStyle(lineWidth: 1, dash: i == 3 ? [] : [2, 4]))
            }
            guard active else { return }

            func line(_ value: KeyPath<TunnelStore.Sample, Double>) -> Path {
                var p = Path()
                var prev: CGPoint?
                for (i, s) in samples.enumerated() {
                    let pt = CGPoint(x: CGFloat(i) * step, y: size.height - CGFloat(s[keyPath: value] / peak) * (size.height - 3) - 1.5)
                    if let prev {
                        let mid = CGPoint(x: (prev.x + pt.x) / 2, y: (prev.y + pt.y) / 2)
                        p.addQuadCurve(to: mid, control: prev)
                    } else {
                        p.move(to: pt)
                    }
                    prev = pt
                }
                if let prev { p.addLine(to: prev) }
                return p
            }

            for (key, color) in [(\TunnelStore.Sample.tx, Theme.sky), (\TunnelStore.Sample.rx, Theme.mint)] {
                let l = line(key)
                var area = l
                area.addLine(to: CGPoint(x: size.width, y: size.height))
                area.addLine(to: CGPoint(x: 0, y: size.height))
                area.closeSubpath()
                ctx.fill(area, with: .linearGradient(Gradient(colors: [color.opacity(0.22), color.opacity(0)]),
                                                     startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                ctx.stroke(l, with: .color(color.opacity(0.95)), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }
        }
    }
}

enum LatencyGrade {
    static func color(_ ms: Double?) -> Color {
        guard let ms else { return Theme.rose }
        return ms < 120 ? Theme.mint : ms < 250 ? Theme.amber : Theme.rose
    }

    static func word(_ ms: Double?) -> String {
        guard let ms else { return L("Yanıt yok", "No response") }
        return ms < 60 ? L("Çok iyi", "Excellent") : ms < 120 ? L("İyi", "Good") : ms < 250 ? L("Orta", "Fair") : L("Yavaş", "Slow")
    }
}

struct LatencyBars: View {
    let values: [Double?]
    var active = true

    var body: some View {
        Canvas { ctx, size in
            let n = max(values.count, 1)
            let slot = size.width / CGFloat(n)
            let w = max(slot - 1.5, 1)
            let peak = max(values.compactMap { $0 }.max() ?? 0, 150) * 1.1
            var base = Path()
            base.move(to: CGPoint(x: 0, y: size.height - 0.5))
            base.addLine(to: CGPoint(x: size.width, y: size.height - 0.5))
            ctx.stroke(base, with: .color(.white.opacity(0.08)), lineWidth: 1)
            guard active else { return }
            for (i, v) in values.enumerated() {
                let x = CGFloat(i) * slot + (slot - w) / 2
                if let v {
                    let h = max(CGFloat(v / peak) * (size.height - 2), 2)
                    ctx.fill(Path(roundedRect: CGRect(x: x, y: size.height - h, width: w, height: h), cornerRadius: min(w / 2, 1)),
                             with: .color(LatencyGrade.color(v).opacity(0.75)))
                } else {
                    ctx.fill(Path(CGRect(x: x, y: size.height - 3, width: w, height: 2)), with: .color(Theme.faint.opacity(0.6)))
                }
            }
        }
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    var labelWidth: CGFloat = 84

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .frame(width: labelWidth, alignment: .leading)
            Text(value)
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(value == "—" ? Theme.faint : Theme.text)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .frame(height: 17)
    }
}

struct StatusDot: View {
    let status: TunnelStore.Status
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(status.color)
            .frame(width: size, height: size)
            .shadow(color: status == .connected ? status.color.opacity(0.8) : .clear, radius: 4)
            .animation(.easeInOut(duration: 0.5), value: status)
    }
}
