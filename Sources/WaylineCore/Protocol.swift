import Darwin
import Foundation

public enum DaemonProtocol {
    public static let socketPath = "/var/run/app.wayline.daemon.sock"
    public static let version = 1
}

public enum DaemonRequest: Codable, Sendable {
    case status
    case connect(name: String, config: WGConfig)
    case disconnect
    case setKillSwitch(Bool)
    case setAllowLAN(Bool)
    case setWatchdog(Bool)
}

public struct DaemonEvent: Codable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable { case info, success, warning, error }
    public let id: Int
    public let date: Date
    public let tr: String
    public let en: String
    public let kind: Kind

    public init(id: Int, date: Date = Date(), tr: String, en: String, kind: Kind) {
        self.id = id
        self.date = date
        self.tr = tr
        self.en = en
        self.kind = kind
    }
}

public struct DaemonStatus: Codable, Sendable, Equatable {
    public enum Phase: String, Codable, Sendable { case down, connecting, up, reconnecting }

    public var version: Int = DaemonProtocol.version
    public var phase: Phase = .down
    public var desired: String?
    public var tunnel: String?
    public var interface: String?
    public var addresses: [String] = []
    public var dns: [String] = []
    public var mtu: Int?
    public var since: Date?
    public var rx: UInt64 = 0
    public var tx: UInt64 = 0
    public var killSwitch = false
    public var allowLAN = true
    public var watchdog = true
    public var events: [DaemonEvent] = []

    public init() {}

    public static func == (a: DaemonStatus, b: DaemonStatus) -> Bool {
        a.phase == b.phase && a.desired == b.desired && a.tunnel == b.tunnel && a.interface == b.interface
            && a.rx == b.rx && a.tx == b.tx && a.killSwitch == b.killSwitch && a.allowLAN == b.allowLAN
            && a.watchdog == b.watchdog && a.events.last?.id == b.events.last?.id && a.since == b.since
    }
}

public struct DaemonResponse: Codable, Sendable {
    public var ok: Bool
    public var error: String?
    public var status: DaemonStatus?

    public init(ok: Bool, error: String? = nil, status: DaemonStatus? = nil) {
        self.ok = ok
        self.error = error
        self.status = status
    }
}

public enum SocketIO {
    public static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    public static func readLine(_ fd: Int32) -> Data? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16384)
        while data.count < 1 << 20 {
            let n = read(fd, &buffer, buffer.count)
            if n <= 0 { return data.isEmpty ? nil : data }
            if let nl = buffer[0..<n].firstIndex(of: 10) {
                data.append(contentsOf: buffer[0..<nl])
                return data
            }
            data.append(contentsOf: buffer[0..<n])
        }
        return nil
    }

    public static func writeLine(_ fd: Int32, _ data: Data) -> Bool {
        var payload = data
        payload.append(10)
        return payload.withUnsafeBytes { raw -> Bool in
            var offset = 0
            while offset < raw.count {
                let n = write(fd, raw.baseAddress! + offset, raw.count - offset)
                if n <= 0 { return false }
                offset += n
            }
            return true
        }
    }

    public static func address(_ path: String) -> sockaddr_un {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            let bytes = Array(path.utf8.prefix(raw.count - 1))
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        return addr
    }

    public static func send(_ request: DaemonRequest, timeout: TimeInterval = 20) throws -> DaemonResponse {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw POSIXError(.EIO) }
        defer { close(fd) }
        var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var addr = address(DaemonProtocol.socketPath)
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .ECONNREFUSED) }
        guard writeLine(fd, try encoder.encode(request)), let line = readLine(fd) else {
            throw POSIXError(.EPIPE)
        }
        return try decoder.decode(DaemonResponse.self, from: line)
    }
}
