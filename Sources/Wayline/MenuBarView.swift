import AppKit
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var store: TunnelStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let target = store.live?.name ?? store.desired ?? store.selected
        let status = target.map { store.status(of: $0) } ?? .disconnected
        let endpoint = target.map { store.mapEndpoint(for: $0) } ?? (location: nil, isExit: false)

        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                WaylineMark(color: status.color, size: 22)
                    .animation(.easeInOut(duration: 0.6), value: status)
                VStack(alignment: .leading, spacing: 1) {
                    Text(target ?? L("Tünel yok", "No tunnel")).font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(store.setup == .ready ? status.title : L("Servis kurulmadı", "Service not installed"))
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .foregroundStyle(status.color)
                        .animation(.easeInOut(duration: 0.5), value: status)
                }
                Spacer()
                if let target, store.setup == .ready {
                    Toggle("", isOn: Binding(
                        get: { status != .disconnected && status != .disconnecting },
                        set: { _ in store.toggle(target) }
                    ))
                    .toggleStyle(.switch)
                    .tint(Theme.mint)
                    .labelsHidden()
                }
            }

            ZStack(alignment: .bottomLeading) {
                Theme.sea
                RouteMap(home: store.homeLocation, server: endpoint.location, status: status,
                         insets: EdgeInsets(top: 22, leading: 30, bottom: 34, trailing: 30),
                         showsLabels: false, minDotSpacing: 4.5,
                         throughput: store.live == nil ? 0 : store.rxRate + store.txRate)
                LinearGradient(colors: [Theme.sea.opacity(0), Theme.sea.opacity(0.9)], startPoint: .center, endPoint: .bottom)
                    .allowsHitTesting(false)
                route(home: store.homeLocation, server: endpoint.location, status: status)
                    .padding(.horizontal, 10).padding(.bottom, 8)
            }
            .frame(height: 128)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.stroke))

            HStack(spacing: 0) {
                metric("arrow.down", store.live == nil ? "—" : Format.rate(store.rxRate), Theme.mint)
                metric("arrow.up", store.live == nil ? "—" : Format.rate(store.txRate), Theme.sky)
                metric("waveform.path.ecg", store.live == nil ? "—" : Format.latency(store.latency),
                       store.live == nil ? Theme.faint : LatencyGrade.color(store.latency))
            }

            if store.tunnels.count > 1 {
                Divider()
                ForEach(store.tunnels, id: \.self) { name in
                    Button {
                        store.selected = name
                        if store.status(of: name) == .disconnected {
                            Task { await store.connect(name) }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            StatusDot(status: store.status(of: name))
                            Text(name).font(.system(size: 12)).lineLimit(1)
                            Spacer(minLength: 8)
                            if let s = store.serverLocations[name] {
                                Text("\(s.flag) \(s.place)").font(.system(size: 11)).foregroundStyle(Theme.muted)
                                    .lineLimit(1)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()
            HStack {
                Button(L("Wayline'ı aç", "Open Wayline")) {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button(L("Çık", "Quit")) { NSApp.terminate(nil) }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(Theme.muted)
        }
        .padding(14)
        .id(store.languageID)
        .frame(width: 300)
        .tracksWindowVisibility()
        .background(Theme.background)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private func route(home: GeoLocation?, server: GeoLocation?, status: TunnelStore.Status) -> some View {
        HStack(spacing: 6) {
            Text(home.map { "\($0.flag) \($0.place)" } ?? L("Konum bilinmiyor", "Location unknown"))
            Image(systemName: "arrow.right").font(.system(size: 8, weight: .bold))
                .foregroundStyle(status == .connected ? Theme.mint : Theme.faint)
            Text(server.map { "\($0.flag) \($0.place)" } ?? "—")
            Spacer(minLength: 0)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(Theme.text.opacity(0.9))
        .lineLimit(1)
    }

    private func metric(_ icon: String, _ text: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 10, weight: .bold)).foregroundStyle(color)
            Text(text).font(.system(size: 12, weight: .medium, design: .rounded)).monospacedDigit()
                .foregroundStyle(text == "—" ? Theme.faint : Theme.text)
                .lineLimit(1)
                .valueGlow(text, color: color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
