import Foundation
import WaylineCore

final class Engine {
    static let helperDirectory = "/Library/PrivilegedHelperTools/app.wayline"
    static let stateDirectory = "/Library/Application Support/Wayline"
    static let staleAfter: TimeInterval = 180
    static let firstHandshakeTimeout: TimeInterval = 20

    let queue = DispatchQueue(label: "app.wayline.engine")

    private struct Persisted: Codable {
        var desiredName: String?
        var desiredConfig: WGConfig?
        var killSwitch = false
        var allowLAN = true
        var watchdog = true
        var resolved: [String: String] = [:]
    }

    private struct Running {
        let name: String
        let config: WGConfig
        let process: Child
        let interface: String
        let since: Date
        var endpoints: [(ip: String, port: UInt16, publicKey: String)]
        var gateway: SystemNetwork.Gateway?
        var mtu: Int
    }

    private var persisted = Persisted()
    private var running: Running?
    private var stats = UAPI.Stats()
    private var events: [DaemonEvent] = []
    private var lastEventID = 0
    private var everConnected = false
    private var softAttempts = 0
    private var lastSoft = Date.distantPast
    private var lastHard = Date.distantPast
    private var backoff: TimeInterval = 5
    private var timer: DispatchSourceTimer?

    func start() {
        queue.sync {
            load()
            Shell.run("/usr/bin/pkill", ["-f", "\(Self.helperDirectory)/wireguard-go"])
            SystemNetwork.unpublish()
            if persisted.desiredName == nil || !persisted.killSwitch { KillSwitch.clear(force: true) }
            if let name = persisted.desiredName, let config = persisted.desiredConfig {
                event("Servis başladı, \(name) yeniden açılıyor", "Service started, reopening \(name)", .info)
                bringUp(name, config)
            }
        }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 3, repeating: 3)
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
    }

    func shutdown() {
        queue.sync { tearDown(keepKillSwitch: persisted.killSwitch) }
    }

    func handle(_ request: DaemonRequest) -> DaemonResponse {
        queue.sync {
            switch request {
            case .status:
                refreshStats()
            case let .connect(name, config):
                persisted.desiredName = name
                persisted.desiredConfig = config
                save()
                everConnected = false
                resetHealth()
                tearDown(keepKillSwitch: true)
                event("\(name) açılıyor", "Opening \(name)", .info)
                bringUp(name, config)
            case .disconnect:
                let name = persisted.desiredName ?? running?.name
                persisted.desiredName = nil
                persisted.desiredConfig = nil
                save()
                tearDown(keepKillSwitch: false)
                if let name { event("\(name) kapatıldı", "\(name) closed", .info) }
            case let .setKillSwitch(on):
                persisted.killSwitch = on
                save()
                updateKillSwitch()
                event(on ? "Kill switch açıldı" : "Kill switch kapatıldı", on ? "Kill switch on" : "Kill switch off", .info)
            case let .setAllowLAN(on):
                persisted.allowLAN = on
                save()
                updateKillSwitch()
            case let .setWatchdog(on):
                persisted.watchdog = on
                save()
            }
            return DaemonResponse(ok: true, status: snapshot())
        }
    }

    private func bringUp(_ name: String, _ config: WGConfig) {
        lastHard = Date()
        do {
            running = try establish(name, config)
            stats = UAPI.Stats()
            updateKillSwitch()
        } catch {
            let e = error as? DaemonError
            event("Tünel kurulamadı: \(e?.tr ?? error.localizedDescription)",
                  "Couldn't set up the tunnel: \(e?.en ?? error.localizedDescription)", .error)
            tearDown(keepKillSwitch: true)
        }
    }

    private func establish(_ name: String, _ config: WGConfig) throws -> Running {
        var timing = Timing()
        var endpoints: [(ip: String, port: UInt16, publicKey: String)] = []
        for peer in config.peers {
            guard let text = peer.endpoint, let ep = Endpoint(text) else { continue }
            guard let ip = Resolver.resolve(ep.host) ?? cachedEndpoint(peer.publicKey) else {
                throw DaemonError("Sunucu adresi çözülemedi: \(ep.host)", "Couldn't resolve server address: \(ep.host)")
            }
            endpoints.append((ip, ep.port, peer.publicKey))
            persisted.resolved[peer.publicKey] = ip
        }
        save()
        let gateway = SystemNetwork.physicalGateway()
        timing.mark("resolve")

        let before = UAPI.sockets()
        let logFD = open("/Library/Logs/Wayline/wireguard-go.log", O_WRONLY | O_APPEND | O_CREAT, 0o644)
        let pid = Shell.spawn("\(Self.helperDirectory)/wireguard-go", ["-f", "utun"],
                              environment: Shell.environment + ["WG_PROCESS_FOREGROUND=1", "LOG_LEVEL=error"],
                              stdout: logFD >= 0 ? logFD : nil)
        if logFD >= 0 { close(logFD) }
        guard let pid else { throw DaemonError("wireguard-go başlatılamadı", "wireguard-go failed to start") }
        let process = Child(pid: pid)

        var iface: String?
        for _ in 0..<1000 {
            if let sock = UAPI.sockets().first(where: { before[$0.key] != $0.value })?.key {
                iface = String(sock.dropLast(5))
                break
            }
            if !process.isRunning { break }
            usleep(5_000)
        }
        guard let iface else {
            process.stop()
            throw DaemonError("wireguard-go başlatılamadı", "wireguard-go failed to start")
        }
        timing.mark("wireguard-go")

        var body = ["private_key=\(WGKey.hex(config.privateKey) ?? "")", "replace_peers=true"]
        if let port = config.listenPort { body.append("listen_port=\(port)") }
        for peer in config.peers {
            body.append("public_key=\(WGKey.hex(peer.publicKey) ?? "")")
            if let psk = peer.presharedKey, let hex = WGKey.hex(psk) { body.append("preshared_key=\(hex)") }
            if let ep = endpoints.first(where: { $0.publicKey == peer.publicKey }) {
                body.append("endpoint=\(Resolver.isIPv6(ep.ip) ? "[\(ep.ip)]" : ep.ip):\(ep.port)")
            }
            if let keepalive = peer.keepalive { body.append("persistent_keepalive_interval=\(keepalive)") }
            body.append("replace_allowed_ips=true")
            body += peer.allowedIPs.map { "allowed_ip=\($0)" }
        }
        do {
            try UAPI.set(iface, body.joined(separator: "\n"))
            timing.mark("uapi")
        } catch {
            process.stop()
            throw error
        }

        let mtu = config.mtu ?? max(1280, (gateway.flatMap { SystemNetwork.interfaceMTU($0.interface) } ?? 1500) - 80)
        for address in config.addresses {
            if address.contains(":") {
                Shell.run("/sbin/ifconfig", [iface, "inet6", address, "alias"])
            } else {
                let ip = String(address.split(separator: "/")[0])
                Shell.run("/sbin/ifconfig", [iface, "inet", address, ip, "alias"])
            }
        }
        Shell.run("/sbin/ifconfig", [iface, "mtu", "\(mtu)", "up"])
        timing.mark("ifconfig")

        let allowed = Set(config.peers.flatMap(\.allowedIPs))
        for cidr in allowed {
            switch cidr {
            case "0.0.0.0/0":
                SystemNetwork.addRoute("0.0.0.0/1", interface: iface)
                SystemNetwork.addRoute("128.0.0.0/1", interface: iface)
            case "::/0":
                SystemNetwork.addRoute("::/1", interface: iface)
                SystemNetwork.addRoute("8000::/1", interface: iface)
            default:
                SystemNetwork.addRoute(cidr, interface: iface)
            }
        }
        if let gateway {
            for ep in endpoints { SystemNetwork.addHostRoute(ep.ip, via: gateway) }
        }
        timing.mark("routes")

        SystemNetwork.publish(interface: iface, addresses: config.addresses, dns: config.dns, fullTunnel: config.isFullTunnel)

        timing.mark("dns")
        log("tunnel \(name) up on \(iface) in \(timing.summary)")
        return Running(name: name, config: config, process: process, interface: iface, since: Date(),
                       endpoints: endpoints, gateway: gateway, mtu: mtu)
    }

    private func tearDown(keepKillSwitch: Bool) {
        if let running {
            var timing = Timing()
            SystemNetwork.unpublish()
            running.process.stop()
            timing.mark("wireguard-go")
            for ep in running.endpoints { SystemNetwork.deleteHostRoute(ep.ip) }
            timing.mark("routes")
            log("tunnel \(running.name) down in \(timing.summary)")
        }
        running = nil
        stats = UAPI.Stats()
        if !keepKillSwitch || !persisted.killSwitch || persisted.desiredName == nil {
            KillSwitch.clear()
        } else {
            updateKillSwitch()
        }
    }

    private func updateKillSwitch() {
        guard persisted.killSwitch, persisted.desiredName != nil else {
            KillSwitch.clear()
            return
        }
        let endpoints = running?.endpoints.map { (ip: $0.ip, port: $0.port) } ?? cachedEndpoints()
        KillSwitch.apply(interface: running?.interface, endpoints: endpoints, allowLAN: persisted.allowLAN)
    }

    private func cachedEndpoints() -> [(ip: String, port: UInt16)] {
        (persisted.desiredConfig?.peers ?? []).compactMap { peer in
            guard let ep = peer.endpoint.flatMap(Endpoint.init) else { return nil }
            let ip = Resolver.isLiteral(ep.host) ? ep.host : cachedEndpoint(peer.publicKey)
            return ip.map { ($0, ep.port) }
        }
    }

    private func cachedEndpoint(_ publicKey: String) -> String? {
        running?.endpoints.first { $0.publicKey == publicKey }?.ip ?? persisted.resolved[publicKey]
    }

    private func tick() {
        refreshStats()
        guard let name = persisted.desiredName, let config = persisted.desiredConfig else { return }
        let now = Date()

        guard let current = running, current.process.isRunning else {
            guard persisted.watchdog || running == nil, now.timeIntervalSince(lastHard) > backoff else { return }
            if running != nil {
                event("wireguard-go durdu, tünel yeniden kuruluyor", "wireguard-go stopped, rebuilding the tunnel", .warning)
            }
            tearDown(keepKillSwitch: true)
            backoff = min(backoff * 2, 120)
            bringUp(name, config)
            return
        }

        let gateway = SystemNetwork.physicalGateway()
        if let gateway, gateway != current.gateway {
            for ep in current.endpoints { SystemNetwork.addHostRoute(ep.ip, via: gateway) }
            running?.gateway = gateway
            event("Ağ değişti (\(gateway.interface)), bağlantı taşınıyor", "Network changed (\(gateway.interface)), moving the connection", .info)
            softReconnect()
            return
        }

        guard persisted.watchdog else { return }
        let reference = stats.lastHandshake ?? current.since
        let limit = stats.lastHandshake == nil ? Self.firstHandshakeTimeout : Self.staleAfter
        guard now.timeIntervalSince(reference) > limit else {
            softAttempts = 0
            backoff = 5
            return
        }
        if softAttempts < 2, now.timeIntervalSince(lastSoft) > 15 {
            event("Sunucudan yanıt yok, el sıkışma yenileniyor", "No response from server, renewing handshake", .warning)
            softReconnect()
        } else if now.timeIntervalSince(lastSoft) > 15, now.timeIntervalSince(lastHard) > backoff {
            event("Yanıt gelmiyor, tünel baştan kuruluyor", "Still no response, rebuilding the tunnel", .warning)
            backoff = min(backoff * 2, 120)
            softAttempts = 0
            tearDown(keepKillSwitch: true)
            bringUp(name, config)
        }
    }

    private func softReconnect() {
        guard let current = running else { return }
        lastSoft = Date()
        softAttempts += 1
        var body: [String] = []
        for peer in current.config.peers {
            guard let ep = peer.endpoint.flatMap(Endpoint.init) else { continue }
            let ip = Resolver.resolve(ep.host) ?? cachedEndpoint(peer.publicKey) ?? ep.host
            body += ["public_key=\(WGKey.hex(peer.publicKey) ?? "")", "update_only=true",
                     "endpoint=\(Resolver.isIPv6(ip) ? "[\(ip)]" : ip):\(ep.port)"]
        }
        try? UAPI.set(current.interface, body.joined(separator: "\n"))
    }

    private func resetHealth() {
        softAttempts = 0
        backoff = 5
        lastSoft = .distantPast
        lastHard = .distantPast
    }

    private func refreshStats() {
        guard let current = running, let fresh = UAPI.stats(current.interface) else { return }
        if fresh.lastHandshake != nil, stats.lastHandshake == nil || !isHealthy(stats) {
            if isHealthy(fresh) {
                event(everConnected ? "Bağlantı toparlandı" : "\(current.name) bağlandı",
                      everConnected ? "Connection recovered" : "\(current.name) connected", .success)
                everConnected = true
            }
        }
        stats = fresh
    }

    private func isHealthy(_ s: UAPI.Stats) -> Bool {
        guard let hs = s.lastHandshake else { return false }
        return Date().timeIntervalSince(hs) < Self.staleAfter
    }

    private func snapshot() -> DaemonStatus {
        var s = DaemonStatus()
        s.desired = persisted.desiredName
        s.killSwitch = persisted.killSwitch
        s.allowLAN = persisted.allowLAN
        s.watchdog = persisted.watchdog
        s.events = Array(events.suffix(30))
        if let current = running {
            s.tunnel = current.name
            s.interface = current.interface
            s.addresses = current.config.addresses
            s.dns = current.config.dns
            s.mtu = current.mtu
            s.since = current.since
            s.rx = stats.rx
            s.tx = stats.tx
            s.phase = isHealthy(stats) ? .up : (everConnected ? .reconnecting : .connecting)
        } else {
            s.phase = persisted.desiredName == nil ? .down : (everConnected ? .reconnecting : .connecting)
        }
        return s
    }

    private func event(_ tr: String, _ en: String, _ kind: DaemonEvent.Kind) {
        let id = max(lastEventID + 1, Int(Date().timeIntervalSince1970 * 1000))
        lastEventID = id
        events.append(DaemonEvent(id: id, tr: tr, en: en, kind: kind))
        if events.count > 60 { events.removeFirst(events.count - 60) }
        log("[\(kind.rawValue)] \(en)")
    }

    private var stateURL: URL { URL(fileURLWithPath: "\(Self.stateDirectory)/state.json") }

    private func load() {
        guard let data = try? Data(contentsOf: stateURL),
              let decoded = try? JSONDecoder().decode(Persisted.self, from: data) else { return }
        persisted = decoded
    }

    private func save() {
        try? FileManager.default.createDirectory(atPath: Self.stateDirectory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        FileManager.default.createFile(atPath: stateURL.path, contents: data, attributes: [.posixPermissions: 0o600])
    }
}

struct Timing {
    private let start = DispatchTime.now().uptimeNanoseconds
    private var last = DispatchTime.now().uptimeNanoseconds
    private var steps: [String] = []

    mutating func mark(_ step: String) {
        let now = DispatchTime.now().uptimeNanoseconds
        steps.append("\(step) \((now - last) / 1_000_000)")
        last = now
    }

    var summary: String {
        "\((DispatchTime.now().uptimeNanoseconds - start) / 1_000_000) ms (\(steps.joined(separator: ", ")))"
    }
}
