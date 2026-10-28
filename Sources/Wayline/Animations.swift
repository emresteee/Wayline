import AppKit
import SwiftUI

private struct WindowVisibleKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var windowVisible: Bool {
        get { self[WindowVisibleKey.self] }
        set { self[WindowVisibleKey.self] = newValue }
    }
}

private struct TracksWindowVisibility: ViewModifier {
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .environment(\.windowVisible, visible)
            .background(WindowVisibilityReader(visible: $visible))
    }
}

extension View {
    func tracksWindowVisibility() -> some View { modifier(TracksWindowVisibility()) }
}

private struct WindowVisibilityReader: NSViewRepresentable {
    @Binding var visible: Bool

    func makeNSView(context: Context) -> Probe {
        let probe = Probe()
        probe.onChange = { visible = $0 }
        return probe
    }

    func updateNSView(_ view: Probe, context: Context) {}

    final class Probe: NSView {
        var onChange: ((Bool) -> Void)?
        private var observers: [NSObjectProtocol] = []
        private var reported: Bool?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers = []
            if let window {
                observers.append(NotificationCenter.default.addObserver(
                    forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.report() }
                })
            }
            report()
        }

        private func report() {
            let visible = window.map { $0.isVisible && $0.occlusionState.contains(.visible) } ?? false
            guard visible != reported else { return }
            reported = visible
            DispatchQueue.main.async { [weak self] in self?.onChange?(visible) }
        }
    }
}

@MainActor
final class MotionClock: ObservableObject {
    static let shared = MotionClock()
    static let interval = 1.0 / 24

    @Published private(set) var now = Date()
    private var timer: Timer?
    private var users = 0

    func retain() {
        users += 1
        guard timer == nil else { return }
        now = Date()
        let timer = Timer(timeInterval: Self.interval, repeats: true) { _ in
            MainActor.assumeIsolated { MotionClock.shared.now = Date() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func release() {
        users = max(users - 1, 0)
        guard users == 0 else { return }
        timer?.invalidate()
        timer = nil
    }
}

struct MotionFrame {
    let date: Date
}

struct Motion<Content: View>: View {
    let active: Bool
    @ViewBuilder let content: (MotionFrame) -> Content

    var body: some View {
        if active {
            Running(content: content)
        } else {
            content(MotionFrame(date: Date()))
        }
    }

    private struct Running: View {
        @ObservedObject private var clock = MotionClock.shared
        let content: (MotionFrame) -> Content

        var body: some View {
            content(MotionFrame(date: clock.now))
                .onAppear { clock.retain() }
                .onDisappear { clock.release() }
        }
    }
}

struct AuroraBackground: View {
    var status: TunnelStore.Status
    @Environment(\.windowVisible) private var windowVisible

    private var moving: Bool { status != .disconnected && windowVisible }

    private static let blobs: [(x: Double, y: Double, r: Double, period: Double, tinted: Bool, k: Double)] = [
        (0.70, 0.42, 0.46, 41, true, 1.0),
        (0.48, 0.80, 0.38, 57, false, 0.55),
        (0.90, 0.18, 0.30, 73, true, 0.7),
    ]

    private var strength: Double {
        switch status {
        case .connected: 0.13
        case .connecting, .reconnecting: 0.09
        case .disconnecting, .disconnected: 0.045
        }
    }

    var body: some View {
        GeometryReader { geo in
            Motion(active: moving) { timeline in
                let t = moving ? timeline.date.timeIntervalSinceReferenceDate : 0
                ZStack {
                    ForEach(Self.blobs.indices, id: \.self) { i in
                        let b = Self.blobs[i]
                        let phase = t / b.period * 2 * .pi + Double(i) * 1.7
                        let d = max(geo.size.width, geo.size.height) * b.r * 2
                        AuroraSprite.image(b.tinted ? status.color : Theme.sky)
                            .resizable()
                            .frame(width: d, height: d)
                            .opacity(strength * b.k)
                            .position(x: geo.size.width * (b.x + 0.06 * sin(phase)),
                                      y: geo.size.height * (b.y + 0.08 * cos(phase * 0.8)))
                            .id(b.tinted ? "\(i)-\(status)" : "\(i)")
                            .transition(.opacity)
                    }
                }
            }
        }
        .clipped()
        .animation(.easeInOut(duration: 1.2), value: status)
        .allowsHitTesting(false)
    }
}

@MainActor
private enum AuroraSprite {
    private static var cache: [String: Image] = [:]

    static func image(_ color: Color) -> Image {
        let key = color.description
        if let image = cache[key] { return image }
        let side = 512
        let image: Image
        if let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                               space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
           let cg = NSColor(color).usingColorSpace(.deviceRGB)?.cgColor,
           let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: [cg, cg.copy(alpha: 0) ?? cg] as CFArray, locations: [0, 1]) {
            let c = CGPoint(x: side / 2, y: side / 2)
            ctx.drawRadialGradient(gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: CGFloat(side / 2), options: [])
            image = ctx.makeImage().map { Image(decorative: $0, scale: 1) } ?? Image(nsImage: NSImage())
        } else {
            image = Image(nsImage: NSImage())
        }
        cache[key] = image
        return image
    }
}

struct FadeIn: ViewModifier {
    var delay: Double = 0
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .onAppear {
                withAnimation(.easeOut(duration: 0.55).delay(delay)) { shown = true }
            }
    }
}

extension View {
    func fadeIn(delay: Double = 0) -> some View { modifier(FadeIn(delay: delay)) }
}

struct ValueGlow: ViewModifier {
    let value: String
    var color: Color = Theme.mint
    @Environment(\.windowVisible) private var windowVisible
    @State private var changedAt: Date?

    private static let duration = 1.3

    func body(content: Content) -> some View {
        Motion(active: changedAt != nil && windowVisible) { timeline in
            let glow = level(at: timeline.date)
            content
                .shadow(color: color.opacity(0.55 * glow), radius: glow > 0 ? 7 : 0)
                .brightness(0.12 * glow)
        }
        .onChange(of: value) { old, new in
            guard old != new, new != "—", old != "—", windowVisible else { return }
            let stamp = Date()
            changedAt = stamp
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.duration) {
                if changedAt == stamp { changedAt = nil }
            }
        }
    }

    private func level(at date: Date) -> Double {
        guard let changedAt else { return 0 }
        let t = min(max(date.timeIntervalSince(changedAt) / Self.duration, 0), 1)
        return (1 - t) * (1 - t)
    }
}

extension View {
    func valueGlow(_ value: String, color: Color = Theme.mint) -> some View {
        modifier(ValueGlow(value: value, color: color))
    }
}

final class Smoothed {
    private(set) var value: Double
    private var last: Double?

    init(_ value: Double = 0) { self.value = value }

    func step(to target: Double, at time: Double, tau: Double = 1.2) -> Double {
        let dt = last.map { min(max(time - $0, 0), 0.5) } ?? 0
        last = time
        value += (target - value) * (1 - exp(-dt / tau))
        return value
    }
}
