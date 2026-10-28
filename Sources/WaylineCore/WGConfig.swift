import CryptoKit
import Foundation

public struct WGConfig: Codable, Equatable, Sendable {
    public struct Peer: Codable, Equatable, Sendable {
        public var publicKey: String
        public var presharedKey: String?
        public var endpoint: String?
        public var allowedIPs: [String]
        public var keepalive: Int?

        public init(publicKey: String, presharedKey: String? = nil, endpoint: String? = nil,
                    allowedIPs: [String] = [], keepalive: Int? = nil) {
            self.publicKey = publicKey
            self.presharedKey = presharedKey
            self.endpoint = endpoint
            self.allowedIPs = allowedIPs
            self.keepalive = keepalive
        }
    }

    public var privateKey: String
    public var addresses: [String]
    public var dns: [String]
    public var mtu: Int?
    public var listenPort: Int?
    public var peers: [Peer]

    public init(privateKey: String, addresses: [String] = [], dns: [String] = [], mtu: Int? = nil,
                listenPort: Int? = nil, peers: [Peer] = []) {
        self.privateKey = privateKey
        self.addresses = addresses
        self.dns = dns
        self.mtu = mtu
        self.listenPort = listenPort
        self.peers = peers
    }

    public struct ParseError: LocalizedError, Equatable {
        public let tr: String
        public let en: String
        public var errorDescription: String? { en }

        public init(tr: String, en: String) {
            self.tr = tr
            self.en = en
        }
    }

    public var isFullTunnel: Bool { peers.contains { $0.allowedIPs.contains("0.0.0.0/0") } }

    public var publicKey: String? { WGKey.publicKey(fromPrivate: privateKey) }

    public static func parse(_ text: String) throws -> WGConfig {
        var section = ""
        var privateKey: String?
        var addresses: [String] = [], dns: [String] = []
        var mtu: Int?, listenPort: Int?
        var peers: [Peer] = []

        for (number, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = raw.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            if line.hasPrefix("[") {
                section = line.lowercased().replacingOccurrences(of: " ", with: "")
                if section == "[peer]" { peers.append(Peer(publicKey: "")) }
                else if section != "[interface]" {
                    throw ParseError(tr: "\(number + 1). satırda bilinmeyen bölüm: \(line)",
                                     en: "Unknown section on line \(number + 1): \(line)")
                }
                continue
            }
            guard let eq = line.firstIndex(of: "=") else {
                throw ParseError(tr: "\(number + 1). satır anlaşılamadı", en: "Couldn't read line \(number + 1)")
            }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            let list = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

            switch (section, key) {
            case ("[interface]", "privatekey"): privateKey = value
            case ("[interface]", "address"): addresses += list
            case ("[interface]", "dns"): dns += list
            case ("[interface]", "mtu"): mtu = Int(value)
            case ("[interface]", "listenport"): listenPort = Int(value)
            case ("[peer]", "publickey"): peers[peers.count - 1].publicKey = value
            case ("[peer]", "presharedkey"): peers[peers.count - 1].presharedKey = value
            case ("[peer]", "endpoint"): peers[peers.count - 1].endpoint = value
            case ("[peer]", "allowedips"): peers[peers.count - 1].allowedIPs += list
            case ("[peer]", "persistentkeepalive"): peers[peers.count - 1].keepalive = Int(value)
            default:
                continue
            }
        }

        guard let privateKey, WGKey.isValid(privateKey) else {
            throw ParseError(tr: "[Interface] bölümünde geçerli bir PrivateKey yok", en: "No valid PrivateKey in [Interface]")
        }
        guard !addresses.isEmpty else {
            throw ParseError(tr: "[Interface] bölümünde Address yok", en: "No Address in [Interface]")
        }
        guard !peers.isEmpty else {
            throw ParseError(tr: "En az bir [Peer] bölümü gerekli", en: "At least one [Peer] section is required")
        }
        for (i, peer) in peers.enumerated() {
            guard WGKey.isValid(peer.publicKey) else {
                throw ParseError(tr: "\(i + 1). [Peer] için PublicKey geçersiz", en: "Invalid PublicKey for [Peer] \(i + 1)")
            }
            if let psk = peer.presharedKey, !WGKey.isValid(psk) {
                throw ParseError(tr: "\(i + 1). [Peer] için PresharedKey geçersiz", en: "Invalid PresharedKey for [Peer] \(i + 1)")
            }
            if let endpoint = peer.endpoint, Endpoint(endpoint) == nil {
                throw ParseError(tr: "Uç nokta anlaşılamadı: \(endpoint)", en: "Couldn't read endpoint: \(endpoint)")
            }
        }
        return WGConfig(privateKey: privateKey, addresses: addresses, dns: dns, mtu: mtu, listenPort: listenPort, peers: peers)
    }

    public var text: String {
        var lines = ["[Interface]", "PrivateKey = \(privateKey)", "Address = \(addresses.joined(separator: ", "))"]
        if !dns.isEmpty { lines.append("DNS = \(dns.joined(separator: ", "))") }
        if let mtu { lines.append("MTU = \(mtu)") }
        if let listenPort { lines.append("ListenPort = \(listenPort)") }
        for peer in peers {
            lines += ["", "[Peer]", "PublicKey = \(peer.publicKey)"]
            if let psk = peer.presharedKey { lines.append("PresharedKey = \(psk)") }
            if let endpoint = peer.endpoint { lines.append("Endpoint = \(endpoint)") }
            if !peer.allowedIPs.isEmpty { lines.append("AllowedIPs = \(peer.allowedIPs.joined(separator: ", "))") }
            if let keepalive = peer.keepalive { lines.append("PersistentKeepalive = \(keepalive)") }
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

public struct Endpoint: Equatable, Sendable {
    public let host: String
    public let port: UInt16

    public init?(_ text: String) {
        let s = text.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("["), let close = s.firstIndex(of: "]") {
            host = String(s[s.index(after: s.startIndex)..<close])
            let rest = s[s.index(after: close)...]
            guard rest.hasPrefix(":"), let p = UInt16(rest.dropFirst()) else { return nil }
            port = p
        } else {
            guard let colon = s.lastIndex(of: ":"), let p = UInt16(s[s.index(after: colon)...]) else { return nil }
            host = String(s[..<colon])
            port = p
        }
        if host.isEmpty { return nil }
    }
}

public enum WGKey {
    public static func isValid(_ base64: String) -> Bool {
        Data(base64Encoded: base64)?.count == 32
    }

    public static func hex(_ base64: String) -> String? {
        guard let data = Data(base64Encoded: base64), data.count == 32 else { return nil }
        return data.map { String(format: "%02x", $0) }.joined()
    }

    public static func base64(fromHex hex: String) -> String? {
        var bytes = [UInt8]()
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return bytes.count == 32 ? Data(bytes).base64EncodedString() : nil
    }

    public static func publicKey(fromPrivate base64: String) -> String? {
        guard let data = Data(base64Encoded: base64),
              let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data) else { return nil }
        return key.publicKey.rawRepresentation.base64EncodedString()
    }

    public static func generate() -> (privateKey: String, publicKey: String) {
        let key = Curve25519.KeyAgreement.PrivateKey()
        return (key.rawRepresentation.base64EncodedString(), key.publicKey.rawRepresentation.base64EncodedString())
    }
}
