import Darwin
import Foundation
import WaylineCore

final class Server {
    private let engine: Engine
    private var listener: Int32 = -1
    private var source: DispatchSourceRead?
    private let connections = DispatchQueue(label: "app.wayline.connections", attributes: .concurrent)

    init(engine: Engine) {
        self.engine = engine
    }

    func start() throws {
        let path = DaemonProtocol.socketPath
        unlink(path)
        listener = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listener >= 0 else { throw POSIXError(.EIO) }
        var addr = SocketIO.address(path)
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, listen(listener, 16) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EADDRINUSE) }
        chmod(path, 0o666)

        let source = DispatchSource.makeReadSource(fileDescriptor: listener, queue: connections)
        source.setEventHandler { [weak self] in self?.accept() }
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        close(listener)
        unlink(DaemonProtocol.socketPath)
    }

    private func accept() {
        let fd = Darwin.accept(listener, nil, nil)
        guard fd >= 0 else { return }
        connections.async { [engine] in
            defer { close(fd) }
            var tv = timeval(tv_sec: 10, tv_usec: 0)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            var nosigpipe: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))

            let response: DaemonResponse
            if !Self.authorized(fd) {
                response = DaemonResponse(ok: false, error: "Not authorized")
            } else if let line = SocketIO.readLine(fd),
                      let request = try? SocketIO.decoder.decode(DaemonRequest.self, from: line) {
                response = engine.handle(request)
            } else {
                response = DaemonResponse(ok: false, error: "Bad request")
            }
            if let data = try? SocketIO.encoder.encode(response) {
                _ = SocketIO.writeLine(fd, data)
            }
        }
    }

    private static func authorized(_ fd: Int32) -> Bool {
        var uid: uid_t = 0, gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0 else { return false }
        if uid == 0 { return true }
        let ownerPath = "\(Engine.stateDirectory)/owner"
        if let owner = try? String(contentsOfFile: ownerPath, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines), uid_t(owner) == uid {
            return true
        }
        guard let pw = getpwuid(uid) else { return false }
        var groups = [Int32](repeating: 0, count: 64)
        var count: Int32 = 64
        getgrouplist(pw.pointee.pw_name, Int32(pw.pointee.pw_gid), &groups, &count)
        return groups.prefix(Int(max(count, 0))).contains(80)
    }
}
