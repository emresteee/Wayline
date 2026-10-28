import Darwin
import Foundation
import SystemConfiguration
import WaylineCore

enum Shell {
    static let environment = ["PATH=/usr/bin:/bin:/usr/sbin:/sbin"]

    static func spawn(_ tool: String, _ args: [String], environment: [String] = environment,
                      stdin: Int32? = nil, stdout: Int32? = nil) -> pid_t? {
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        posix_spawn_file_actions_init(&actions)
        posix_spawnattr_init(&attributes)
        defer {
            posix_spawn_file_actions_destroy(&actions)
            posix_spawnattr_destroy(&attributes)
        }
        var noSignals = sigset_t(), allSignals = sigset_t()
        sigemptyset(&noSignals)
        sigfillset(&allSignals)
        posix_spawnattr_setsigmask(&attributes, &noSignals)
        posix_spawnattr_setsigdefault(&attributes, &allSignals)
        posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF))
        if let stdin {
            posix_spawn_file_actions_adddup2(&actions, stdin, 0)
        } else {
            posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        }
        if let stdout {
            posix_spawn_file_actions_adddup2(&actions, stdout, 1)
            posix_spawn_file_actions_adddup2(&actions, stdout, 2)
        } else {
            posix_spawn_file_actions_addopen(&actions, 1, "/dev/null", O_WRONLY, 0)
            posix_spawn_file_actions_addopen(&actions, 2, "/dev/null", O_WRONLY, 0)
        }
        let argv = ([tool] + args).map { strdup($0) } + [nil]
        let envp = environment.map { strdup($0) } + [nil]
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }
        var pid: pid_t = 0
        guard posix_spawn(&pid, tool, &actions, &attributes, argv, envp) == 0 else { return nil }
        return pid
    }

    @discardableResult
    static func run(_ tool: String, _ args: [String], input: String? = nil) -> (status: Int32, output: String) {
        var output: [Int32] = [-1, -1]
        var source: [Int32] = [-1, -1]
        guard pipe(&output) == 0 else { return (-1, "") }
        if input != nil, pipe(&source) != 0 {
            close(output[0])
            close(output[1])
            return (-1, "")
        }
        let pid = spawn(tool, args, stdin: input == nil ? nil : source[0], stdout: output[1])
        close(output[1])
        if input != nil { close(source[0]) }
        guard let pid else {
            close(output[0])
            if input != nil { close(source[1]) }
            return (-1, "")
        }
        if let input {
            let bytes = Array(input.utf8)
            var offset = 0
            while offset < bytes.count {
                let n = bytes.withUnsafeBufferPointer { write(source[1], $0.baseAddress! + offset, bytes.count - offset) }
                if n <= 0 { break }
                offset += n
            }
            close(source[1])
        }
        var data = [UInt8]()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(output[0], &buffer, buffer.count)
            if n <= 0 { break }
            data.append(contentsOf: buffer[0..<n])
        }
        close(output[0])
        var status: Int32 = 0
        while waitpid(pid, &status, 0) < 0, errno == EINTR {}
        return ((status & 0x7f) == 0 ? (status >> 8) & 0xff : -1, String(decoding: data, as: UTF8.self))
    }
}

final class Child {
    let pid: pid_t
    private var exited = false

    init(pid: pid_t) { self.pid = pid }

    var isRunning: Bool {
        guard !exited else { return false }
        var status: Int32 = 0
        let result = waitpid(pid, &status, WNOHANG)
        if result == pid || (result < 0 && errno == ECHILD) { exited = true }
        return !exited
    }

    func stop() {
        guard isRunning else { return }
        kill(pid, SIGTERM)
        for _ in 0..<400 {
            usleep(5_000)
            if !isRunning { return }
        }
        kill(pid, SIGKILL)
        var status: Int32 = 0
        waitpid(pid, &status, 0)
        exited = true
    }
}

private let stampFormatter = ISO8601DateFormatter()

func log(_ message: String) {
    FileHandle.standardError.write(Data("\(stampFormatter.string(from: Date())) \(message)\n".utf8))
}

enum UAPI {
    static let directory = "/var/run/wireguard"

    static func path(_ iface: String) -> String { "\(directory)/\(iface).sock" }

    static func sockets() -> [String: ino_t] {
        var result: [String: ino_t] = [:]
        for name in (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
        where name.hasPrefix("utun") && name.hasSuffix(".sock") {
            var info = stat()
            if lstat("\(directory)/\(name)", &info) == 0 { result[name] = info.st_ino }
        }
        return result
    }

    static func exchange(_ iface: String, _ request: String) throws -> String {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        defer { close(fd) }
        var tv = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var nosigpipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))
        var addr = SocketIO.address(path(iface))
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard ok == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .ECONNREFUSED) }
        let payload = Array(request.utf8)
        var offset = 0
        while offset < payload.count {
            let n = payload.withUnsafeBufferPointer { write(fd, $0.baseAddress! + offset, payload.count - offset) }
            guard n > 0 else { throw POSIXError(.EPIPE) }
            offset += n
        }

        var response = [UInt8]()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = read(fd, &buffer, buffer.count)
            if n <= 0 { break }
            response.append(contentsOf: buffer[0..<n])
            if response.count >= 2, response[response.count - 2] == 10, response[response.count - 1] == 10 { break }
        }
        return String(decoding: response, as: UTF8.self)
    }

    static func set(_ iface: String, _ body: String) throws {
        let reply = try exchange(iface, "set=1\n\(body)\n\n")
        guard reply.contains("errno=0") else {
            let detail = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            throw DaemonError("wireguard-go yapılandırmayı reddetti (\(detail))", "wireguard-go rejected the configuration (\(detail))")
        }
    }

    struct Stats {
        var rx: UInt64 = 0
        var tx: UInt64 = 0
        var lastHandshake: Date?
    }

    static func stats(_ iface: String) -> Stats? {
        guard let reply = try? exchange(iface, "get=1\n\n") else { return nil }
        var stats = Stats()
        for line in reply.split(separator: "\n") {
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq], value = line[line.index(after: eq)...]
            switch key {
            case "rx_bytes": stats.rx += UInt64(value) ?? 0
            case "tx_bytes": stats.tx += UInt64(value) ?? 0
            case "last_handshake_time_sec":
                if let s = TimeInterval(value), s > 0 {
                    let date = Date(timeIntervalSince1970: s)
                    stats.lastHandshake = max(stats.lastHandshake ?? date, date)
                }
            default: break
            }
        }
        return stats
    }
}

struct DaemonError: LocalizedError {
    let tr: String
    let en: String
    init(_ tr: String, _ en: String) {
        self.tr = tr
        self.en = en
    }
    var errorDescription: String? { en }
}

enum Resolver {
    static func isLiteral(_ host: String) -> Bool {
        var v4 = in_addr(), v6 = in6_addr()
        return inet_pton(AF_INET, host, &v4) == 1 || inet_pton(AF_INET6, host, &v6) == 1
    }

    static func resolve(_ host: String) -> String? {
        if isLiteral(host) { return host }
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_DGRAM
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else { return nil }
        defer { freeaddrinfo(result) }
        var v4: String?, v6: String?
        var cursor: UnsafeMutablePointer<addrinfo>? = first
        while let info = cursor {
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(info.pointee.ai_addr, info.pointee.ai_addrlen, &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                let ip = String(cString: buffer)
                if info.pointee.ai_family == AF_INET, v4 == nil { v4 = ip }
                if info.pointee.ai_family == AF_INET6, v6 == nil { v6 = ip }
            }
            cursor = info.pointee.ai_next
        }
        return v4 ?? v6
    }

    static func isIPv6(_ ip: String) -> Bool { ip.contains(":") }
}

enum SystemNetwork {
    static let serviceID = "app.wayline.tunnel"
    private static let store = SCDynamicStoreCreate(nil, "wayline-daemon" as CFString, nil, nil)

    struct Gateway: Equatable {
        var router: String?
        var interface: String
    }

    static func physicalGateway() -> Gateway? {
        guard let store else { return nil }
        let order = (SCDynamicStoreCopyValue(store, "Setup:/Network/Global/IPv4" as CFString) as? [String: Any])?["ServiceOrder"] as? [String] ?? []
        let keys = SCDynamicStoreCopyKeyList(store, "State:/Network/Service/[^/]+/IPv4" as CFString) as? [String] ?? []
        var candidates: [(id: String, ipv4: [String: Any])] = []
        for key in keys {
            let id = key.split(separator: "/")[3]
            guard id != serviceID, let ipv4 = SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any] else { continue }
            candidates.append((String(id), ipv4))
        }
        candidates.sort { (order.firstIndex(of: $0.id) ?? Int.max) < (order.firstIndex(of: $1.id) ?? Int.max) }
        for candidate in candidates {
            guard let iface = candidate.ipv4["InterfaceName"] as? String,
                  !iface.hasPrefix("utun"), !iface.hasPrefix("ipsec"), !iface.hasPrefix("ppp") else { continue }
            if let router = candidate.ipv4["Router"] as? String {
                return Gateway(router: router, interface: iface)
            }
        }
        return nil
    }

    static func publish(interface: String, addresses: [String], dns: [String], fullTunnel: Bool) {
        guard let store else { return }
        unpublish()
        let v4 = addresses.filter { !$0.contains(":") }.map { String($0.split(separator: "/")[0]) }
        let v6 = addresses.filter { $0.contains(":") }.map { String($0.split(separator: "/")[0]) }

        if !v4.isEmpty {
            var ipv4: [String: Any] = [
                "Addresses": v4,
                "SubnetMasks": v4.map { _ in "255.255.255.255" },
                "InterfaceName": interface,
                "Router": v4[0],
            ]
            if fullTunnel { ipv4["OverridePrimary"] = 1 }
            SCDynamicStoreAddTemporaryValue(store, key("IPv4"), ipv4 as CFDictionary)
        }
        if !v6.isEmpty {
            var ipv6: [String: Any] = [
                "Addresses": v6,
                "PrefixLength": v6.map { _ in 128 },
                "InterfaceName": interface,
                "Router": v6[0],
            ]
            if fullTunnel { ipv6["OverridePrimary"] = 1 }
            SCDynamicStoreAddTemporaryValue(store, key("IPv6"), ipv6 as CFDictionary)
        }
        let servers = dns.filter(Resolver.isLiteral)
        let search = dns.filter { !Resolver.isLiteral($0) }
        if !servers.isEmpty {
            var dnsDict: [String: Any] = ["ServerAddresses": servers]
            if !search.isEmpty { dnsDict["SearchDomains"] = search }
            if !fullTunnel { dnsDict["SupplementalMatchDomains"] = search.isEmpty ? [""] : search }
            SCDynamicStoreAddTemporaryValue(store, key("DNS"), dnsDict as CFDictionary)
        }
    }

    static func unpublish() {
        guard let store else { return }
        for entity in ["IPv4", "IPv6", "DNS"] {
            SCDynamicStoreRemoveValue(store, key(entity))
        }
    }

    private static func key(_ entity: String) -> CFString {
        "State:/Network/Service/\(serviceID)/\(entity)" as CFString
    }

    static func addRoute(_ cidr: String, interface: String) {
        let family = cidr.contains(":") ? "-inet6" : "-inet"
        Shell.run("/sbin/route", ["-q", "-n", "add", family, cidr, "-interface", interface])
    }

    static func addHostRoute(_ ip: String, via gateway: Gateway) {
        let family = Resolver.isIPv6(ip) ? "-inet6" : "-inet"
        deleteHostRoute(ip)
        if let router = gateway.router, Resolver.isIPv6(router) == Resolver.isIPv6(ip) {
            Shell.run("/sbin/route", ["-q", "-n", "add", family, ip, router])
        } else {
            Shell.run("/sbin/route", ["-q", "-n", "add", family, ip, "-interface", gateway.interface])
        }
    }

    static func deleteHostRoute(_ ip: String) {
        let family = Resolver.isIPv6(ip) ? "-inet6" : "-inet"
        Shell.run("/sbin/route", ["-q", "-n", "delete", family, ip])
    }

    static func interfaceMTU(_ iface: String) -> Int? {
        let out = Shell.run("/sbin/ifconfig", [iface]).output
        guard let range = out.range(of: #"mtu (\d+)"#, options: .regularExpression) else { return nil }
        return Int(out[range].split(separator: " ")[1])
    }
}

enum KillSwitch {
    static let anchor = "com.apple/250.Wayline"
    private static var token: String?
    private static var applied = false

    static func apply(interface: String?, endpoints: [(ip: String, port: UInt16)], allowLAN: Bool) {
        var rules = ["pass out quick on lo0 all"]
        if let interface { rules.append("pass out quick on \(interface) all") }
        for ep in endpoints {
            let family = Resolver.isIPv6(ep.ip) ? "inet6" : "inet"
            rules.append("pass out quick \(family) proto udp from any to \(ep.ip) port \(ep.port)")
        }
        rules += [
            "pass out quick inet proto udp from any port 68 to any port 67",
            "pass out quick inet6 proto icmp6 all",
            "pass out quick inet6 proto udp from any port 546 to any port 547",
        ]
        if allowLAN {
            rules += [
                "pass out quick inet from any to { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16, 224.0.0.0/4, 255.255.255.255 }",
                "pass out quick inet6 from any to { fe80::/10, ff00::/8, fc00::/7 }",
            ]
        }
        rules.append("block drop out quick all")
        ensureMainRuleset()
        Shell.run("/sbin/pfctl", ["-q", "-a", anchor, "-f", "-"], input: rules.joined(separator: "\n") + "\n")
        applied = true
        if token == nil {
            let out = Shell.run("/sbin/pfctl", ["-E"]).output
            if let range = out.range(of: #"Token : (\d+)"#, options: .regularExpression) {
                token = String(out[range].split(separator: " ").last ?? "")
            }
        }
    }

    static func clear(force: Bool = false) {
        guard applied || force || token != nil else { return }
        Shell.run("/sbin/pfctl", ["-q", "-a", anchor, "-F", "rules"])
        applied = false
        if let token {
            Shell.run("/sbin/pfctl", ["-X", token])
            self.token = nil
        }
    }

    private static func ensureMainRuleset() {
        let rules = Shell.run("/sbin/pfctl", ["-s", "rules"]).output
        if !rules.contains("com.apple/*") {
            Shell.run("/sbin/pfctl", ["-q", "-f", "/etc/pf.conf"])
        }
    }
}
