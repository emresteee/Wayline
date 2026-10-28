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

struct AuroraBackground: View {
    var status: TunnelStore.Status
    @Environment(\.windowVisible) private var windowVisible

    private var moving: Bool { status != .disconnected && windowVisible }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 10, paused: !moving)) { timeline in
            let t = moving ? timeline.date.timeIntervalSinceReferenceDate : 0
            Canvas { ctx, size in
                let tint = status.color
                let strength: Double = switch status {
                case .connected: 0.13
                case .connecting, .reconnecting: 0.09
                case .disconnecting, .disconnected: 0.045
                }
                let blobs: [(x: Double, y: Double, r: Double, p: Double, c: Color, k: Double)] = [
                    (0.70, 0.42, 0.46, 41, tint, 1.0),
                    (0.48, 0.80, 0.38, 57, Theme.sky, 0.55),
                    (0.90, 0.18, 0.30, 73, tint, 0.7),
                ]
                for (i, b) in blobs.enumerated() {
                    let phase = t / b.p * 2 * .pi + Double(i) * 1.7
                    let center = CGPoint(x: size.width * (b.x + 0.06 * sin(phase)),
                                         y: size.height * (b.y + 0.08 * cos(phase * 0.8)))
                    let r = max(size.width, size.height) * b.r
                    let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
                        .intersection(CGRect(origin: .zero, size: size))
                    guard !rect.isNull else { continue }
                    ctx.fill(Path(rect), with: .radialGradient(
                        Gradient(colors: [b.c.opacity(strength * b.k), b.c.opacity(0)]),
                        center: center, startRadius: 0, endRadius: r))
                }
            }
        }
        .animation(.easeInOut(duration: 1.2), value: status)
        .allowsHitTesting(false)
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
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: changedAt == nil || !windowVisible)) { timeline in
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
