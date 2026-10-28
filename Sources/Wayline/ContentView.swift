import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WaylineCore

struct ContentView: View {
    @EnvironmentObject private var store: TunnelStore
    @StateObject private var ui = UIState()

    var body: some View {
        Group {
            switch store.setup {
            case .checking:
                ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
            case .needsService, .serviceOutdated:
                SetupView()
            case .ready:
                MainView()
            }
        }
        .id(store.languageID)
        .environmentObject(ui)
        .frame(width: 1100, height: 720)
        .tracksWindowVisibility()
        .foregroundStyle(Theme.text)
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .alert(L("Bir sorun oluştu", "Something went wrong"), isPresented: Binding(
            get: { store.errorMessage != nil && !ui.showSettings },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button(L("Tamam", "OK"), role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
        .sheet(item: $ui.editor) { target in
            EditorView(target: target)
                .environmentObject(store)
        }
        .sheet(isPresented: $ui.showSettings) {
            SettingsView()
                .environmentObject(store)
        }
        .alert(L("Tünel silinsin mi?", "Delete this tunnel?"), isPresented: Binding(
            get: { ui.confirmDelete != nil },
            set: { if !$0 { ui.confirmDelete = nil } }
        ), presenting: ui.confirmDelete) { name in
            Button(L("Sil", "Delete"), role: .destructive) { Task { await store.deleteTunnel(name) } }
            Button(L("Vazgeç", "Cancel"), role: .cancel) {}
        } message: { name in
            Text(L("\(name) ve anahtarları bu Mac'ten kalıcı olarak silinir. Gerekirse önce dışa aktar.",
                   "\(name) and its keys are permanently removed from this Mac. Export it first if you need it."))
        }
    }
}

enum EditorTarget: Identifiable, Equatable {
    case new
    case edit(String)

    var id: String {
        switch self {
        case .new: "+new"
        case .edit(let name): "edit:" + name
        }
    }
}

@MainActor
final class UIState: ObservableObject {
    @Published var editor: EditorTarget?
    @Published var showSettings = false
    @Published var importing = false
    @Published var confirmDelete: String?
}

extension TunnelStore {
    func mapEndpoint(for name: String) -> (location: GeoLocation?, isExit: Bool) {
        if live?.name == name, let exit = exitLocation { return (exit, true) }
        return (serverLocations[name], false)
    }

    func exportTunnel(_ name: String) {
        guard let text = configText(for: name) else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(name).conf"
        panel.allowedContentTypes = [UTType(filenameExtension: "conf") ?? .plainText]
        panel.canCreateDirectories = true
        panel.message = L("Yapılandırma özel anahtarını içerir; güvenli bir yerde sakla.",
                          "The configuration contains its private key; keep it somewhere safe.")
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try text.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                Task { @MainActor in
                    self.errorMessage = L("Dışa aktarılamadı: ", "Couldn't export: ") + error.localizedDescription
                }
            }
        }
    }
}

enum ImportTypes {
    static let content: [UTType] = [UTType(filenameExtension: "conf") ?? .plainText, .plainText, .image]

    static func accepts(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "conf" || QRImport.imageExtensions.contains(ext)
    }
}

enum Distance {
    private static let formatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    static func text(_ a: GeoLocation, _ b: GeoLocation) -> String {
        let km = a.point.distance(to: b.point)
        let f = formatter
        f.locale = AppLanguage.locale
        return "\(f.string(from: NSNumber(value: (km / 10).rounded() * 10)) ?? "\(Int(km))") km"
    }
}

struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color.black.opacity(0.85))
            .padding(.horizontal, 18).padding(.vertical, 9)
            .background(Theme.mint.opacity(configuration.isPressed ? 0.75 : 1), in: Capsule())
            .contentShape(Capsule())
    }
}

struct QuietButtonStyle: ButtonStyle {
    var tint: Color = Theme.text

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(tint.opacity(configuration.isPressed ? 0.7 : 0.92))
            .padding(.horizontal, 14).padding(.vertical, 7)
            .background(Theme.panelRaised.opacity(configuration.isPressed ? 0.6 : 1), in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.strokeStrong))
            .contentShape(Capsule())
    }
}

private struct MainView: View {
    @EnvironmentObject private var store: TunnelStore
    @EnvironmentObject private var ui: UIState
    @State private var dropTargeted = false

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
                .frame(width: 240)
                .background(Theme.sidebar)
            Rectangle().fill(Theme.stroke).frame(width: 1)
            Group {
                if let name = store.selected, store.tunnels.contains(name) {
                    TunnelDetail(name: name).id(name)
                } else {
                    EmptyState()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(Theme.mint, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                .background(Theme.mint.opacity(0.05))
                .overlay {
                    VStack(spacing: 4) {
                        Text(L("Bırak, Wayline'a eklensin", "Drop to add to Wayline"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.mint)
                        Text(L(".conf dosyası ya da QR kodlu görsel", ".conf file or an image with a QR code"))
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.muted)
                    }
                    .padding(.horizontal, 20).padding(.vertical, 11)
                    .background(Theme.background.opacity(0.92), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(10)
                .opacity(dropTargeted ? 1 : 0)
                .animation(.easeInOut(duration: 0.25), value: dropTargeted)
                .allowsHitTesting(false)
        }
        .dropDestination(for: URL.self) { urls, _ in
            let accepted = urls.filter(ImportTypes.accepts)
            Task { for url in accepted { await store.importConfig(from: url) } }
            return !accepted.isEmpty
        } isTargeted: { dropTargeted = $0 }
        .fileImporter(isPresented: $ui.importing, allowedContentTypes: ImportTypes.content,
                      allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            Task { for url in urls { await store.importConfig(from: url) } }
        }
    }
}

@MainActor
enum PopupMenu {
    private final class Item: NSObject {
        let action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
        @objc func run() { action() }
    }

    static func show(_ items: [(String, () -> Void)]) {
        let menu = NSMenu()
        var targets: [Item] = []
        for (title, action) in items {
            let target = Item(action)
            targets.append(target)
            let item = NSMenuItem(title: title, action: #selector(Item.run), keyEquivalent: "")
            item.target = target
            menu.addItem(item)
        }
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow, let view = window.contentView else { return }
        let point = view.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        _ = withExtendedLifetime(targets) {
            menu.popUp(positioning: nil, at: point, in: view)
        }
    }
}

private struct Sidebar: View {
    @EnvironmentObject private var store: TunnelStore
    @EnvironmentObject private var ui: UIState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                WaylineMark(color: store.status.color, size: 24)
                    .animation(.easeInOut(duration: 0.6), value: store.status)
                Text("Wayline").font(Theme.display(18))
            }
            .padding(.horizontal, 18)
            .padding(.top, 44)
            .padding(.bottom, 24)

            SectionLabel(text: L("Tüneller", "Tunnels")).padding(.horizontal, 18).padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 3) {
                    ForEach(store.tunnels, id: \.self) { name in
                        TunnelRow(name: name, selected: store.selected == name)
                            .onTapGesture { store.selected = name }
                            .contextMenu {
                                Button(L("Düzenle…", "Edit…")) { ui.editor = .edit(name) }
                                Button(L("Dışa aktar…", "Export…")) { store.exportTunnel(name) }
                                Divider()
                                Button(L("Sil…", "Delete…"), role: .destructive) { ui.confirmDelete = name }
                            }
                    }
                }
                .padding(.horizontal, 10)
            }

            Button {
                PopupMenu.show([
                    (L("Dosyadan içe aktar…", "Import from file…"), { ui.importing = true }),
                    (L("Yeni tünel…", "New tunnel…"), { ui.editor = .new }),
                ])
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                        .frame(width: 14)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(L("Tünel ekle", "Add tunnel")).font(.system(size: 12, weight: .medium))
                        Text(L(".conf, QR kodu ya da yeni", ".conf, QR code or new"))
                            .font(.system(size: 10)).foregroundStyle(Theme.faint)
                    }
                    .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 8.5, weight: .semibold))
                        .foregroundStyle(Theme.faint)
                }
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 9).strokeBorder(Theme.strokeStrong, style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 10)
            .padding(.vertical, 12)

            Rectangle().fill(Theme.stroke).frame(height: 1)

            ProtectionSummary()
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Button {
                ui.showSettings = true
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: "gearshape").font(.system(size: 12, weight: .medium)).frame(width: 14)
                    Text(L("Ayarlar", "Settings")).font(.system(size: 12.5, weight: .medium))
                    Spacer(minLength: 0)
                    Text("⌘,").font(.system(size: 11)).foregroundStyle(Theme.faint)
                }
                .foregroundStyle(Theme.text.opacity(0.85))
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(Theme.panelRaised, in: RoundedRectangle(cornerRadius: 9))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(",", modifiers: .command)
            .padding(.horizontal, 10)
            .padding(.bottom, 14)
        }
    }
}

private struct ProtectionSummary: View {
    @EnvironmentObject private var store: TunnelStore

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            row("arrow.triangle.2.circlepath", L("Bağlantı koruması", "Connection guard"), store.watchdogEnabled)
            row("lock.shield", "Kill switch", store.killSwitch)
            row("wifi", L("Wi-Fi'de otomatik", "Auto on Wi-Fi"), store.autoConnect)
        }
    }

    private func row(_ icon: String, _ title: String, _ on: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(on ? Theme.mint : Theme.faint)
                .frame(width: 14)
            Text(title)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(on ? L("Açık", "On") : L("Kapalı", "Off"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(on ? Theme.mint : Theme.faint)
                .frame(width: 42, alignment: .trailing)
        }
        .frame(height: 16)
        .animation(.easeInOut(duration: 0.4), value: on)
    }
}

private struct TunnelRow: View {
    @EnvironmentObject private var store: TunnelStore
    let name: String
    let selected: Bool

    var body: some View {
        let status = store.status(of: name)
        let server = store.serverLocations[name]
        HStack(spacing: 10) {
            StatusDot(status: status)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                Text(subtitle(status, server))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(status == .disconnected ? Theme.muted : status.color)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .animation(.easeInOut(duration: 0.5), value: status)
            }
            .frame(height: 32)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(selected ? Theme.panelRaised : .clear, in: RoundedRectangle(cornerRadius: 9))
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1).fill(status.color).frame(width: 2, height: 18)
                .opacity(selected ? 1 : 0)
        }
        .contentShape(Rectangle())
    }

    private func subtitle(_ status: TunnelStore.Status, _ server: GeoLocation?) -> String {
        guard status == .disconnected else { return status.title }
        if let server { return "\(server.flag) \(server.place)" }
        return store.endpoints[name] ?? "—"
    }
}

private struct EmptyState: View {
    @EnvironmentObject private var store: TunnelStore
    @EnvironmentObject private var ui: UIState

    var body: some View {
        ZStack {
            RouteMap(home: store.homeLocation, server: nil, status: .disconnected,
                     insets: EdgeInsets(top: 40, leading: 40, bottom: 200, trailing: 40))
                .opacity(0.7)
            LinearGradient(colors: [.clear, Theme.background], startPoint: .center, endPoint: .bottom)
            VStack(spacing: 14) {
                Spacer()
                Text(L("Henüz tünel yok", "No tunnels yet")).font(Theme.display(22))
                Text(L("Bir WireGuard .conf dosyasını ya da QR kodlu bir görseli pencereye sürükle. Sağlayıcın yoksa sıfırdan yeni bir tünel de oluşturabilirsin.",
                       "Drag a WireGuard .conf file or an image with its QR code onto the window. You can also create a new tunnel from scratch."))
                    .multilineTextAlignment(.center)
                    .frame(width: 400)
                    .foregroundStyle(Theme.muted)
                HStack(spacing: 10) {
                    Button(L("Dosya seç", "Choose file")) { ui.importing = true }
                        .buttonStyle(AccentButtonStyle())
                    Button(L("Yeni tünel", "New tunnel")) { ui.editor = .new }
                        .buttonStyle(QuietButtonStyle())
                }
                .padding(.top, 4)
            }
            .padding(.bottom, 70)
            .fadeIn(delay: 0.1)
        }
    }
}

private struct TunnelDetail: View {
    @EnvironmentObject private var store: TunnelStore
    let name: String

    var body: some View {
        let live = store.live?.name == name ? store.live : nil

        VStack(spacing: 12) {
            Hero(name: name)
                .frame(height: 340)
                .fadeIn()

            HStack(spacing: 12) {
                TrafficCard(live: live).fadeIn(delay: 0.08)
                LatencyCard(live: live).frame(width: 232).fadeIn(delay: 0.14)
                SessionCard(live: live).frame(width: 212).fadeIn(delay: 0.20)
            }
            .frame(height: 148)

            HStack(spacing: 12) {
                ConfigCard(name: name, live: live).fadeIn(delay: 0.26)
                EventsCard().fadeIn(delay: 0.32)
            }
            .frame(height: 164)
        }
        .padding(22)
    }
}

private struct Hero: View {
    @EnvironmentObject private var store: TunnelStore
    @EnvironmentObject private var ui: UIState
    let name: String

    private let textWidth: CGFloat = 248

    var body: some View {
        let status = store.status(of: name)
        let endpoint = store.mapEndpoint(for: name)
        let home = store.homeLocation
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)

        ZStack(alignment: .topLeading) {
            Theme.sea
            AuroraBackground(status: status)

            RouteMap(home: home, server: endpoint.location, status: status,
                     insets: EdgeInsets(top: 92, leading: 300, bottom: 64, trailing: 60),
                     serverCaption: endpoint.isExit ? L("Çıkış", "Exit") : L("Sunucu", "Server"),
                     throughput: store.live?.name == name ? store.rxRate + store.txRate : 0)

            LinearGradient(stops: [.init(color: Theme.sea, location: 0), .init(color: Theme.sea.opacity(0.92), location: 0.55),
                                   .init(color: Theme.sea.opacity(0), location: 1)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: 360)
                .allowsHitTesting(false)
            LinearGradient(colors: [Theme.sea.opacity(0), Theme.sea.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                .frame(height: 70)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .allowsHitTesting(false)

            controls(status: status, exit: endpoint.isExit ? endpoint.location : nil, home: home)
                .padding(24)
                .frame(width: 296, alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                routeChip(home: home, server: endpoint.location, status: status)
                menu
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.stroke))
    }

    private func controls(status: TunnelStore.Status, exit: GeoLocation?, home: GeoLocation?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(name)
                .font(Theme.display(24))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: textWidth, alignment: .leading)
            HStack(spacing: 7) {
                StatusDot(status: status)
                Text(status.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(status.color)
                    .lineLimit(1)
                    .animation(.easeInOut(duration: 0.5), value: status)
            }
            .frame(width: textWidth, height: 20, alignment: .leading)
            .padding(.top, 2)

            Spacer(minLength: 12)
            PowerButton(status: status) { store.toggle(name) }
                .padding(.leading, 4)
            Spacer(minLength: 12)

            VStack(alignment: .leading, spacing: 3) {
                Text(headline(status))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.muted)
                Text(place(status, exit, home))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(detail(status, exit, home))
                    .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(status == .connected ? Theme.mint : Theme.muted)
                    .animation(.easeInOut(duration: 0.5), value: status)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(width: textWidth, height: 54, alignment: .topLeading)
        }
    }

    private func headline(_ status: TunnelStore.Status) -> String {
        switch status {
        case .connected: L("Trafiğin tünelden çıkıyor", "Your traffic exits through the tunnel")
        case .connecting: L("Güvenli yol kuruluyor", "Setting up a secure route")
        case .reconnecting: L("Bağlantı toparlanıyor", "Recovering the connection")
        case .disconnecting: L("Tünel kapatılıyor", "Closing the tunnel")
        case .disconnected: L("Trafiğin doğrudan çıkıyor", "Your traffic goes out directly")
        }
    }

    private func place(_ status: TunnelStore.Status, _ exit: GeoLocation?, _ home: GeoLocation?) -> String {
        switch status {
        case .connected: exit.map { "\($0.flag) \($0.place)" } ?? " "
        case .disconnected: home.map { "\($0.flag) \($0.place)" } ?? " "
        default: " "
        }
    }

    private func detail(_ status: TunnelStore.Status, _ exit: GeoLocation?, _ home: GeoLocation?) -> String {
        switch status {
        case .connected: exit.map { "\(L("Görünen IP", "Visible IP")) \($0.ip)" } ?? L("Çıkış IP'si ölçülüyor", "Measuring exit IP")
        case .disconnected: home.map { "\(L("Görünen IP", "Visible IP")) \($0.ip)" } ?? L("Gerçek IP'n görünür", "Your real IP is visible")
        default: L("Bu birkaç saniye sürebilir", "This may take a few seconds")
        }
    }

    private var menu: some View {
        Menu {
            Button(L("Düzenle…", "Edit…")) { ui.editor = .edit(name) }
            Button(L("Dışa aktar…", "Export…")) { store.exportTunnel(name) }
            Divider()
            Button(L("Sil…", "Delete…"), role: .destructive) { ui.confirmDelete = name }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.muted)
                .frame(width: 30, height: 30)
                .background(Theme.background.opacity(0.7), in: Circle())
                .overlay(Circle().strokeBorder(Theme.stroke))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L("Tünel seçenekleri", "Tunnel options"))
    }

    @ViewBuilder
    private func routeChip(home: GeoLocation?, server: GeoLocation?, status: TunnelStore.Status) -> some View {
        if let home, let server {
            HStack(spacing: 8) {
                Text("\(home.flag) \(home.place)")
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(status == .connected ? Theme.mint : Theme.faint)
                Text("\(server.flag) \(server.place)")
                Rectangle().fill(Theme.strokeStrong).frame(width: 1, height: 12)
                Text(Distance.text(home, server))
                    .monospacedDigit()
                    .foregroundStyle(Theme.muted)
            }
            .lineLimit(1)
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(Theme.text.opacity(0.9))
            .padding(.horizontal, 12)
            .frame(height: 30)
            .frame(maxWidth: 440)
            .fixedSize()
            .background(Theme.background.opacity(0.72), in: Capsule())
            .overlay(Capsule().strokeBorder(Theme.stroke))
            .animation(.easeInOut(duration: 0.5), value: status)
        }
    }
}

private struct TrafficCard: View {
    @EnvironmentObject private var store: TunnelStore
    let live: LiveTunnel?

    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    SectionLabel(text: L("Trafik", "Traffic"))
                    Text(L("son 2 dakika", "last 2 minutes")).font(.system(size: 11)).foregroundStyle(Theme.faint)
                        .lineLimit(1)
                    Spacer()
                }
                HStack(spacing: 18) {
                    rate(icon: "arrow.down", value: store.rxRate, color: Theme.mint)
                    rate(icon: "arrow.up", value: store.txRate, color: Theme.sky)
                    Spacer(minLength: 0)
                }
                ThroughputChart(samples: store.history, active: live != nil)
                    .frame(maxHeight: .infinity)
            }
        }
    }

    private func rate(icon: String, value: Double, color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(live == nil ? Theme.faint : color)
            LiveValue(text: live == nil ? "—" : Format.rate(value),
                      color: live == nil ? Theme.faint : Theme.text, size: 20, width: 112, glowColor: color)
        }
    }
}

private struct LatencyCard: View {
    @EnvironmentObject private var store: TunnelStore
    let live: LiveTunnel?

    var body: some View {
        let latency = live == nil ? nil : store.latency
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    SectionLabel(text: L("Gecikme", "Latency"))
                    Spacer(minLength: 4)
                    Text(live == nil ? " " : LatencyGrade.word(latency))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(LatencyGrade.color(latency))
                        .lineLimit(1)
                        .frame(width: 96, alignment: .trailing)
                        .animation(.easeInOut(duration: 0.5), value: latency == nil)
                }
                LiveValue(text: live == nil ? "—" : Format.latency(latency),
                          color: live == nil ? Theme.faint : (latency == nil ? Theme.amber : Theme.text), size: 20,
                          glowColor: LatencyGrade.color(latency))
                LatencyBars(values: store.latencyHistory, active: live != nil)
                    .frame(maxHeight: .infinity)
            }
        }
    }
}

private struct SessionCard: View {
    let live: LiveTunnel?
    @Environment(\.windowVisible) private var windowVisible

    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: L("Oturum", "Session"))
                Motion(active: windowVisible && live != nil) { timeline in
                    LiveValue(text: live?.since.map { Format.duration(timeline.date.timeIntervalSince($0)) } ?? "—",
                              color: live == nil ? Theme.faint : Theme.text, size: 20, glows: false)
                }
                Spacer(minLength: 0)
                VStack(spacing: 5) {
                    total(L("Gelen", "Received"), live.map { Format.bytes($0.rx) }, Theme.mint)
                    total(L("Giden", "Sent"), live.map { Format.bytes($0.tx) }, Theme.sky)
                    total(L("Başlangıç", "Started"), live?.since.map(Format.clock), Theme.slate)
                }
            }
        }
    }

    private func total(_ label: String, _ value: String?, _ color: Color) -> some View {
        HStack(spacing: 7) {
            Circle().fill(value == nil ? Theme.faint : color).frame(width: 5, height: 5)
            Text(label).font(.system(size: 11.5)).foregroundStyle(Theme.muted).lineLimit(1)
            Spacer(minLength: 4)
            Text(value ?? "—")
                .font(.system(size: 11.5, weight: .medium).monospacedDigit())
                .foregroundStyle(value == nil ? Theme.faint : Theme.text)
                .lineLimit(1)
        }
        .frame(height: 15)
    }
}

private struct ConfigCard: View {
    @EnvironmentObject private var store: TunnelStore
    let name: String
    let live: LiveTunnel?

    var body: some View {
        let server = store.serverLocations[name]
        let config = store.configs[name]
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: L("Yapılandırma", "Configuration")).padding(.bottom, 3)
                InfoRow(label: L("Uç nokta", "Endpoint"), value: store.endpoints[name] ?? "—", labelWidth: 92)
                InfoRow(label: L("Sağlayıcı", "Provider"), value: server.map { $0.org.isEmpty ? $0.countryName : $0.org } ?? "—", labelWidth: 92)
                InfoRow(label: L("Adres", "Address"), value: (live?.addresses ?? config?.addresses).map { $0.isEmpty ? "—" : $0.joined(separator: ", ") } ?? "—", labelWidth: 92)
                InfoRow(label: "DNS", value: dns(config), labelWidth: 92)
                InfoRow(label: L("Yönlendirme", "Routing"), value: routing(config), labelWidth: 92)
            }
        }
    }

    private func dns(_ config: WGConfig?) -> String {
        let list = live?.dns ?? config?.dns
        guard let list else { return "—" }
        return list.isEmpty ? L("Sistem", "System") : list.joined(separator: ", ")
    }

    private func routing(_ config: WGConfig?) -> String {
        var parts: [String] = []
        if let config {
            parts.append(config.isFullTunnel ? L("Tüm trafik", "All traffic")
                                             : L("Yalnızca seçili ağlar", "Selected networks only"))
        }
        if let live {
            parts.append(live.interface)
            if let mtu = live.mtu { parts.append("MTU \(mtu)") }
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }
}

private struct EventsCard: View {
    @EnvironmentObject private var store: TunnelStore

    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: L("Olaylar", "Events")).padding(.bottom, 3)
                if store.events.isEmpty {
                    Text(L("Bağlantıyla ilgili her şey burada görünecek.", "Everything about the connection will show up here."))
                        .font(.system(size: 12)).foregroundStyle(Theme.faint)
                        .lineLimit(1)
                        .frame(height: 17)
                }
                ForEach(store.events.prefix(5)) { event in
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Circle().fill(event.kind.color).frame(width: 6, height: 6)
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                        Text(Format.clock(event.date))
                            .font(.system(size: 11).monospacedDigit())
                            .foregroundStyle(Theme.faint)
                            .frame(width: 52, alignment: .leading)
                        Text(event.text)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.text.opacity(0.9))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .frame(height: 17)
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.5), value: store.events.first?.id)
        }
    }
}
