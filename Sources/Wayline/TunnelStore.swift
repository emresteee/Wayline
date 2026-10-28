import AppKit
import Network
import ServiceManagement
import SwiftUI
import WaylineCore

@MainActor
final class TunnelStore: ObservableObject {
    enum Setup { case checking, needsService, serviceOutdated, ready }

    enum Status: Equatable {
        case disconnected, connecting, connected, reconnecting, disconnecting

        var title: String {
            switch self {
            case .disconnected: L("Bağlı değil", "Not connected")
            case .connecting: L("Bağlanıyor", "Connecting")
            case .connected: L("Bağlı", "Connected")
            case .reconnecting: L("Yeniden bağlanıyor", "Reconnecting")
            case .disconnecting: L("Kesiliyor", "Disconnecting")
            }
        }

        var isTransitioning: Bool { self != .connected && self != .disconnected }
    }

    struct Sample: Equatable { var rx: Double; var tx: Double }

    struct Event: Identifiable {
        enum Kind { case info, success, warning, error }
        let id: String
        let date: Date
        let message: LocalizedText
        let kind: Kind
        var text: String { message.string }

        init(id: String = UUID().uuidString, date: Date = Date(), message: LocalizedText, kind: Kind) {
            self.id = id
            self.date = date
            self.message = message
            self.kind = kind
        }
    }

    static let historyLength = 60

    @Published private(set) var setup: Setup = .checking
    @Published private(set) var installing = false
    @Published private(set) var tunnels: [String] = []
    @Published private(set) var configs: [String: WGConfig] = [:]
    @Published var selected: String?
    @Published private(set) var live: LiveTunnel?
    @Published private(set) var rxRate: Double = 0
    @Published private(set) var txRate: Double = 0
    @Published private(set) var history = Array(repeating: Sample(rx: 0, tx: 0), count: historyLength)
    @Published private(set) var latency: Double?
    @Published private(set) var latencyHistory: [Double?] = Array(repeating: nil, count: historyLength)
    @Published private(set) var exitLocation: GeoLocation?
    @Published private(set) var homeLocation: GeoLocation?
    @Published private(set) var serverLocations: [String: GeoLocation] = [:]
    @Published private(set) var events: [Event] = []
    @Published var errorMessage: String?
    @Published private(set) var service = DaemonStatus()
    @Published private var pending: Status?

    var endpoints: [String: String] { configs.compactMapValues { $0.peers.first?.endpoint } }

    @Published var language: AppLanguage = AppLanguage.stored {
        didSet {
            defaults.set(language.rawValue, forKey: "language")
            AppLanguage.resolved = AppLanguage.resolve(language)
        }
    }

    var languageID: AppLanguage { AppLanguage.resolve(language) }

    var watchdogEnabled: Bool {
        get { service.watchdog }
        set { send(.setWatchdog(newValue)) }
    }

    var killSwitch: Bool {
        get { service.killSwitch }
        set { send(.setKillSwitch(newValue)) }
    }

    var allowLAN: Bool {
        get { service.allowLAN }
        set { send(.setAllowLAN(newValue)) }
    }

    @Published var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled {
        didSet {
            guard launchAtLogin != (SMAppService.mainApp.status == .enabled) else { return }
            do {
                if launchAtLogin { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                errorMessage = L("Girişte başlatma ayarlanamadı: ", "Couldn't set launch at login: ") + error.localizedDescription
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    @Published var autoConnect: Bool {
        didSet {
            defaults.set(autoConnect, forKey: "autoConnect")
            if autoConnect {
                if wifi.permission != .granted { wifi.requestPermission() }
                applyWiFiRules(wifi.ssid)
            }
        }
    }

    @Published var trustedNetworks: [String] {
        didSet { defaults.set(trustedNetworks, forKey: "trustedNetworks") }
    }

    @Published var disconnectOnTrusted: Bool {
        didSet { defaults.set(disconnectOnTrusted, forKey: "disconnectOnTrusted") }
    }

    @Published var autoConnectTunnel: String? {
        didSet { defaults.set(autoConnectTunnel, forKey: "autoConnectTunnel") }
    }

    @Published var notificationsEnabled: Bool {
        didSet {
            defaults.set(notificationsEnabled, forKey: "notifications")
            if notificationsEnabled {
                Task {
                    if !(await Notifier.requestAuthorization()) {
                        notificationsEnabled = false
                        errorMessage = L("Bildirim izni verilmedi. Sistem Ayarları › Bildirimler'den açabilirsin.",
                                         "Notification permission was denied. You can enable it in System Settings › Notifications.")
                    }
                }
            }
        }
    }

    @Published var hotkeyEnabled: Bool {
        didSet {
            defaults.set(hotkeyEnabled, forKey: "hotkey")
            hotkeyEnabled ? HotKey.shared.register() : HotKey.shared.unregister()
        }
    }

    var hotkeyLabel: String { HotKey.label }
    var currentSSID: String? { wifi.ssid }
    var wifiPermission: WiFiMonitor.Permission { wifi.permission }

    let wifi = WiFiMonitor()
    private let defaults = UserDefaults.standard
    private var pollTask: Task<Void, Never>?
    private let pathMonitor = NWPathMonitor()
    private var networkSignature: String?
    private var lastSample: (date: Date, rx: UInt64, tx: UInt64, name: String)?
    private var seenServiceEvents = Set<Int>()
    private var lastProbe = Date.distantPast
    private var lastExitLookup = Date.distantPast
    private var lastPhase: DaemonStatus.Phase = .down
    private var phasePrimed = false

    init() {
        autoConnect = defaults.bool(forKey: "autoConnect")
        trustedNetworks = defaults.stringArray(forKey: "trustedNetworks") ?? []
        disconnectOnTrusted = defaults.object(forKey: "disconnectOnTrusted") as? Bool ?? true
        autoConnectTunnel = defaults.string(forKey: "autoConnectTunnel")
        notificationsEnabled = defaults.bool(forKey: "notifications")
        hotkeyEnabled = defaults.object(forKey: "hotkey") as? Bool ?? true
        if let data = defaults.data(forKey: "home"), let home = try? JSONDecoder().decode(GeoLocation.self, from: data) {
            homeLocation = home
        }
        HotKey.shared.handler = { [weak self] in self?.hotkeyPressed() }
        if hotkeyEnabled { HotKey.shared.register() }
        wifi.onChange = { [weak self] ssid in self?.wifiChanged(ssid) }
        observeNetwork()
        Task { await start() }
    }

    var desired: String? { service.desired }

    var focused: String? { live?.name ?? service.desired ?? selected }

    var status: Status { focused.map(status(of:)) ?? .disconnected }

    func status(of name: String) -> Status {
        let isTarget = service.desired == name || service.tunnel == name
        if let pending, isTarget || (pending == .connecting && selected == name && service.desired == nil) { return pending }
        guard isTarget else { return .disconnected }
        switch service.phase {
        case .up: return .connected
        case .connecting: return .connecting
        case .reconnecting: return .reconnecting
        case .down: return service.desired == name ? .reconnecting : .disconnected
        }
    }

    func start() async {
        setup = .checking
        loadTunnels()
        if !ServiceClient.isInstalled {
            setup = .needsService
        } else if !ServiceClient.isCurrent() {
            setup = .serviceOutdated
        } else {
            setup = .ready
        }
        if setup == .ready {
            await refresh()
        }
        if live == nil { Task { await lookupHome() } }
        startPolling()
    }

    func installService() async {
        installing = true
        defer { installing = false }
        do {
            try await ServiceClient.install()
            for _ in 0..<20 {
                if (try? await ServiceClient.send(.status)) != nil { break }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
            await start()
            log("Wayline servisi kuruldu", "Wayline service installed", .success)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func uninstallService() async {
        do {
            try await ServiceClient.uninstall()
            await start()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.setup == .ready {
                    await self.refresh()
                    if self.live != nil, Date().timeIntervalSince(self.lastProbe) >= 4 {
                        self.lastProbe = Date()
                        Task { await self.measureHealth() }
                    }
                }
                let fast = self.pending != nil || self.status.isTransitioning
                try? await Task.sleep(nanoseconds: fast ? 250_000_000 : 2_000_000_000)
            }
        }
    }

    private func send(_ request: DaemonRequest) {
        Task {
            do {
                apply(try await ServiceClient.send(request))
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func loadTunnels() {
        let names = TunnelLibrary.names()
        var loaded: [String: WGConfig] = [:]
        for name in names {
            if let text = TunnelLibrary.text(name), let config = try? WGConfig.parse(text) { loaded[name] = config }
        }
        tunnels = names
        configs = loaded
        if selected == nil || !tunnels.contains(selected!) {
            selected = service.desired.flatMap { tunnels.contains($0) ? $0 : nil } ?? tunnels.first
        }
        for (name, config) in loaded where serverLocations[name] == nil {
            guard let host = config.peers.first?.endpoint.flatMap(Endpoint.init)?.host else { continue }
            Task { if let location = await GeoLocation.lookup(host) { serverLocations[name] = location } }
        }
    }

    func importConfig(from url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let base = url.deletingPathExtension().lastPathComponent
        do {
            if QRImport.imageExtensions.contains(url.pathExtension.lowercased()) {
                guard let payload = QRImport.payloads(in: url).first(where: { (try? WGConfig.parse($0)) != nil }) else {
                    throw WGConfig.ParseError(tr: "Görselde WireGuard QR kodu bulunamadı", en: "No WireGuard QR code found in the image")
                }
                try importConfig(text: payload, name: base)
            } else {
                let data = try Data(contentsOf: url)
                guard data.count < 65536 else {
                    throw WGConfig.ParseError(tr: "Dosya çok büyük", en: "The file is too large")
                }
                try importConfig(text: String(decoding: data, as: UTF8.self), name: base)
            }
        } catch {
            errorMessage = L("İçe aktarılamadı: ", "Couldn't import: ") + localized(error)
        }
    }

    @discardableResult
    func importConfig(text: String, name: String) throws -> String {
        let config = try WGConfig.parse(text)
        let unique = TunnelLibrary.uniqueName(name, excluding: tunnels)
        try TunnelLibrary.save(unique, text: config.text)
        loadTunnels()
        selected = unique
        log("\(unique) eklendi", "\(unique) added", .success)
        return unique
    }

    func configText(for name: String) -> String? { TunnelLibrary.text(name) }

    func saveConfig(name: String, text: String, originalName: String?) throws {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard TunnelLibrary.isValidName(trimmed) else {
            throw WGConfig.ParseError(tr: "Tünel adı geçersiz", en: "Invalid tunnel name")
        }
        let config = try WGConfig.parse(text)
        let others = tunnels.filter { $0 != originalName }
        if others.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            throw WGConfig.ParseError(tr: "Bu adda bir tünel zaten var", en: "A tunnel with this name already exists")
        }
        if let originalName, originalName != trimmed { try TunnelLibrary.rename(originalName, to: trimmed) }
        try TunnelLibrary.save(trimmed, text: config.text)
        serverLocations[trimmed] = nil
        loadTunnels()
        selected = trimmed
        if let originalName, service.desired == originalName {
            Task { await connect(trimmed) }
        }
    }

    func deleteTunnel(_ name: String) async {
        if service.desired == name || service.tunnel == name { await disconnect() }
        do {
            try TunnelLibrary.delete(name)
            log("\(name) silindi", "\(name) deleted", .info)
            if selected == name { selected = nil }
            if autoConnectTunnel == name { autoConnectTunnel = nil }
            loadTunnels()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func newTunnelTemplate() -> String {
        let keys = WGKey.generate()
        return """
        [Interface]
        # \(L("Açık anahtar", "Public key")): \(keys.publicKey)
        PrivateKey = \(keys.privateKey)
        Address = 10.0.0.2/32
        DNS = 1.1.1.1, 1.0.0.1

        [Peer]
        PublicKey =
        Endpoint =
        AllowedIPs = 0.0.0.0/0, ::/0
        PersistentKeepalive = 25

        """
    }

    func generateKeyPair() -> (privateKey: String, publicKey: String) { WGKey.generate() }

    func toggle(_ name: String) {
        Task {
            switch status(of: name) {
            case .disconnected: await connect(name)
            case .disconnecting: break
            default: await disconnect()
            }
        }
    }

    func connect(_ name: String) async {
        guard setup == .ready else { return }
        guard let text = TunnelLibrary.text(name) else { return }
        do {
            let config = try WGConfig.parse(text)
            pending = .connecting
            defer { pending = nil }
            apply(try await ServiceClient.send(.connect(name: name, config: config)))
            lastExitLookup = .distantPast
        } catch {
            errorMessage = localized(error)
        }
    }

    func disconnect() async {
        pending = .disconnecting
        defer { pending = nil }
        do {
            apply(try await ServiceClient.send(.disconnect))
            exitLocation = nil
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                await lookupHome()
            }
        } catch {
            errorMessage = localized(error)
        }
    }

    private func hotkeyPressed() {
        guard let name = focused ?? tunnels.first else { return }
        toggle(name)
    }

    func refresh() async {
        do {
            apply(try await ServiceClient.send(.status))
        } catch {
            if setup == .ready { setup = ServiceClient.isInstalled ? .ready : .needsService }
        }
    }

    private func apply(_ status: DaemonStatus) {
        if service != status { service = status }
        mergeServiceEvents(status.events)
        if phasePrimed { notifyPhaseChange(from: lastPhase, to: status.phase, tunnel: status.tunnel ?? status.desired) }
        phasePrimed = true
        lastPhase = status.phase

        var current: LiveTunnel?
        if let name = status.tunnel, let iface = status.interface {
            current = LiveTunnel(name: name, interface: iface, addresses: status.addresses, dns: status.dns,
                                 since: status.since, rx: status.rx, tx: status.tx, mtu: status.mtu)
        }

        let now = Date()
        if let current, let last = lastSample, last.name == current.name, current.rx >= last.rx, current.tx >= last.tx {
            let dt = now.timeIntervalSince(last.date)
            if dt >= 1 {
                rxRate = Double(current.rx - last.rx) / dt
                txRate = Double(current.tx - last.tx) / dt
                lastSample = (now, current.rx, current.tx, current.name)
                pushSample()
            }
        } else if current?.name != lastSample?.name || current == nil {
            rxRate = 0
            txRate = 0
            lastSample = current.map { (now, $0.rx, $0.tx, $0.name) }
            pushSample()
        }
        if live != current { live = current }
        if current == nil { latency = nil }
    }

    private func pushSample() {
        history.append(Sample(rx: rxRate, tx: txRate))
        if history.count > Self.historyLength { history.removeFirst(history.count - Self.historyLength) }
    }

    private func mergeServiceEvents(_ incoming: [DaemonEvent]) {
        let fresh = incoming.filter { !seenServiceEvents.contains($0.id) }
        guard !fresh.isEmpty else { return }
        fresh.forEach { seenServiceEvents.insert($0.id) }
        for e in fresh {
            let kind: Event.Kind = switch e.kind {
            case .info: .info
            case .success: .success
            case .warning: .warning
            case .error: .error
            }
            events.append(Event(id: "s\(e.id)", date: e.date, message: LocalizedText(tr: e.tr, en: e.en), kind: kind))
        }
        events.sort { $0.date > $1.date }
        if events.count > 50 { events.removeLast(events.count - 50) }
    }

    private func notifyPhaseChange(from old: DaemonStatus.Phase, to new: DaemonStatus.Phase, tunnel: String?) {
        guard notificationsEnabled, old != new, let tunnel else { return }
        switch (old, new) {
        case (.connecting, .up), (.reconnecting, .up):
            Notifier.post("Wayline", L("\(tunnel) bağlandı", "\(tunnel) connected"))
        case (.up, .reconnecting):
            Notifier.post("Wayline", L("Bağlantı koptu, toparlanıyor…", "Connection dropped, recovering…"))
        case (.up, .down) where service.desired == nil:
            Notifier.post("Wayline", L("Bağlantı kesildi", "Disconnected"))
        default:
            break
        }
    }

    private func measureHealth() async {
        let ms = await NetProbe.probe()
        latency = live == nil ? nil : ms
        latencyHistory.append(latency)
        if latencyHistory.count > Self.historyLength { latencyHistory.removeFirst(latencyHistory.count - Self.historyLength) }
        if ms != nil, Date().timeIntervalSince(lastExitLookup) > 600 {
            lastExitLookup = Date()
            if let location = await GeoLocation.lookup() { exitLocation = location }
        }
    }

    private func lookupHome() async {
        guard live == nil, let location = await GeoLocation.lookup(), live == nil else { return }
        homeLocation = location
        if let data = try? JSONEncoder().encode(location) { defaults.set(data, forKey: "home") }
    }

    func trustCurrentNetwork() {
        guard let ssid = wifi.ssid, !trustedNetworks.contains(ssid) else { return }
        trustedNetworks.append(ssid)
    }

    func removeTrustedNetwork(_ ssid: String) {
        trustedNetworks.removeAll { $0 == ssid }
    }

    func requestWiFiPermission() { wifi.requestPermission() }

    private func wifiChanged(_ ssid: String?) {
        objectWillChange.send()
        applyWiFiRules(ssid)
    }

    private func applyWiFiRules(_ ssid: String?) {
        guard autoConnect, setup == .ready, let ssid else { return }
        if trustedNetworks.contains(ssid) {
            if disconnectOnTrusted, service.desired != nil {
                log("Güvenilen ağ (\(ssid)): bağlantı kesiliyor", "Trusted network (\(ssid)): disconnecting", .info)
                Task { await disconnect() }
            }
        } else if service.desired == nil, let name = autoConnectTunnel.flatMap({ tunnels.contains($0) ? $0 : nil }) ?? selected ?? tunnels.first {
            log("Güvenilmeyen ağ (\(ssid)): otomatik bağlanılıyor", "Untrusted network (\(ssid)): connecting automatically", .warning)
            if notificationsEnabled {
                Notifier.post("Wayline", L("\(ssid) güvenilir değil, \(name) açılıyor", "\(ssid) isn't trusted, turning on \(name)"))
            }
            Task { await connect(name) }
        }
    }

    private func observeNetwork() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let signature = path.status == .satisfied
                ? path.availableInterfaces.filter { $0.type != .other }.map(\.name).sorted().joined(separator: ",")
                : "offline"
            Task { @MainActor in self?.networkChanged(signature) }
        }
        pathMonitor.start(queue: DispatchQueue(label: "wayline.path"))
    }

    private func networkChanged(_ signature: String) {
        defer { networkSignature = signature }
        guard let previous = networkSignature, previous != signature else { return }
        wifi.refresh()
        if signature != "offline", service.desired == nil {
            Task { await lookupHome() }
        }
    }

    func log(_ tr: String, _ en: String, _ kind: Event.Kind) {
        events.insert(Event(message: LocalizedText(tr: tr, en: en), kind: kind), at: 0)
        if events.count > 50 { events.removeLast(events.count - 50) }
    }

    private func localized(_ error: Error) -> String {
        if let parse = error as? WGConfig.ParseError { return AppLanguage.resolved == .tr ? parse.tr : parse.en }
        return error.localizedDescription
    }
}
