import AppKit
import Foundation
import WaylineCore

enum ServiceClient {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static var bundledService: URL? { Bundle.main.resourceURL?.appendingPathComponent("Service") }
    static let installedDaemon = "/Library/PrivilegedHelperTools/app.wayline/wayline-daemon"

    static func send(_ request: DaemonRequest) async throws -> DaemonStatus {
        let response = try await Task.detached(priority: .userInitiated) {
            try SocketIO.send(request)
        }.value
        guard response.ok, let status = response.status else {
            throw Failure(message: response.error ?? L("Servis isteği reddetti", "The service rejected the request"))
        }
        return status
    }

    static func isCurrent() -> Bool {
        guard let bundled = bundledService?.appendingPathComponent("wayline-daemon"),
              let a = FileManager.default.contents(atPath: bundled.path),
              let b = FileManager.default.contents(atPath: installedDaemon) else { return false }
        return a == b
    }

    static var isInstalled: Bool { FileManager.default.fileExists(atPath: installedDaemon) }

    static func install() async throws {
        guard let dir = bundledService?.path else {
            throw Failure(message: L("Uygulama paketi eksik, yeniden indirin.", "The app bundle is incomplete, please download it again."))
        }
        try await admin("/bin/bash \(quoted(dir + "/install.sh")) \(quoted(dir)) \(getuid())")
    }

    static func uninstall() async throws {
        guard let dir = bundledService?.path else { return }
        try await admin("/bin/bash \(quoted(dir + "/uninstall.sh"))")
    }

    static func quoted(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func appleScriptLiteral(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func admin(_ command: String) async throws {
        let prompt = L("Wayline, VPN servisini kurmak istiyor.", "Wayline wants to install its VPN service.")
        let script = "do shell script \(appleScriptLiteral(command)) with prompt \(appleScriptLiteral(prompt)) with administrator privileges"
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                let output = String(decoding: data, as: UTF8.self)
                if output.contains("-128") { throw Failure(message: L("Kurulum iptal edildi.", "Installation was cancelled.")) }
                throw Failure(message: output.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }.value
    }
}

enum TunnelLibrary {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Wayline/Tunnels", isDirectory: true)
    }

    static func ensureDirectory() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
    }

    static func names() -> [String] {
        ensureDirectory()
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return files.filter { $0.hasSuffix(".conf") }.map { String($0.dropLast(5)) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func url(_ name: String) -> URL { directory.appendingPathComponent("\(name).conf") }

    static func text(_ name: String) -> String? {
        try? String(contentsOf: url(name), encoding: .utf8)
    }

    static func save(_ name: String, text: String) throws {
        ensureDirectory()
        let target = url(name)
        try Data(text.utf8).write(to: target, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
    }

    static func delete(_ name: String) throws {
        try FileManager.default.removeItem(at: url(name))
    }

    static func rename(_ old: String, to new: String) throws {
        try FileManager.default.moveItem(at: url(old), to: url(new))
    }

    static func uniqueName(_ raw: String, excluding existing: [String]) -> String {
        let cleaned = raw.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let base = String((cleaned.isEmpty ? "Tunnel" : cleaned).prefix(32))
        var name = base
        var n = 2
        while existing.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            name = "\(base) \(n)"
            n += 1
        }
        return name
    }

    static func isValidName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && trimmed.count <= 32 && !trimmed.contains("/") && !trimmed.contains(":") && !trimmed.hasPrefix(".")
    }
}
