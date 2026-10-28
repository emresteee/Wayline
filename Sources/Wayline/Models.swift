import Foundation

struct LiveTunnel: Equatable {
    var name: String
    var interface: String
    var addresses: [String]
    var dns: [String]
    var since: Date?
    var rx: UInt64
    var tx: UInt64
    var mtu: Int?
}

enum Format {
    static func bytes(_ value: UInt64) -> String {
        scaled(Double(value), suffix: "")
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        scaled(bytesPerSecond, suffix: "/s")
    }

    private static func scaled(_ value: Double, suffix: String) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = max(value, 0)
        var unit = 0
        while v >= 1000, unit < units.count - 1 {
            v /= 1024
            unit += 1
        }
        let number = unit == 0 ? String(format: "%.0f", v) : String(format: v < 10 ? "%.2f" : v < 100 ? "%.1f" : "%.0f", v)
        return "\(number) \(units[unit])\(suffix)"
    }

    static func latency(_ ms: Double?) -> String {
        guard let ms else { return "—" }
        return String(format: "%.0f ms", ms)
    }

    static func ago(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "—" }
        let s = max(0, Int(now.timeIntervalSince(date)))
        if s < 60 { return L("\(s) sn önce", "\(s)s ago") }
        if s < 3600 { return L("\(s / 60) dk önce", "\(s / 60)m ago") }
        return L("\(s / 3600) sa önce", "\(s / 3600)h ago")
    }

    static func duration(_ interval: TimeInterval) -> String {
        let s = max(0, Int(interval))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%02d:%02d", m, sec)
    }

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    static func clock(_ date: Date) -> String { clockFormatter.string(from: date) }
}
