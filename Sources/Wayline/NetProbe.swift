import Foundation
import Network

enum NetProbe {
    private static let queue = DispatchQueue(label: "wayline.probe")

    static func probe(host: String = "1.1.1.1", port: UInt16 = 443, timeout: TimeInterval = 3) async -> Double? {
        await withCheckedContinuation { continuation in
            let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
            let started = DispatchTime.now()
            let once = Once()
            @Sendable func finish(_ value: Double?) {
                guard once.claim() else { return }
                connection.cancel()
                continuation.resume(returning: value)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    finish(Double(DispatchTime.now().uptimeNanoseconds - started.uptimeNanoseconds) / 1_000_000)
                case .failed, .cancelled:
                    finish(nil)
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { finish(nil) }
        }
    }
}

private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}

struct GeoLocation: Equatable, Codable {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    var ip: String
    var city: String
    var region: String
    var country: String
    var latitude: Double
    var longitude: Double
    var org: String

    static func lookup(_ ip: String? = nil) async -> GeoLocation? {
        let path = ip.map { "https://ipinfo.io/\($0)/json" } ?? "https://ipinfo.io/json"
        guard let url = URL(string: path) else { return nil }
        guard let (data, _) = try? await session.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let loc = (json["loc"] as? String)?.split(separator: ","), loc.count == 2,
              let lat = Double(loc[0]), let lon = Double(loc[1])
        else { return nil }
        let org = (json["org"] as? String ?? "").replacingOccurrences(of: #"^AS\d+\s+"#, with: "", options: .regularExpression)
        return GeoLocation(ip: json["ip"] as? String ?? ip ?? "", city: json["city"] as? String ?? "",
                           region: json["region"] as? String ?? "", country: json["country"] as? String ?? "",
                           latitude: lat, longitude: lon, org: org)
    }

    var countryName: String {
        AppLanguage.locale.localizedString(forRegionCode: country) ?? country
    }

    var flag: String {
        country.uppercased().unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) }.map(String.init).joined()
    }
}
