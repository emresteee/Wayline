import Darwin
import Foundation
import WaylineCore

guard getuid() == 0 else {
    FileHandle.standardError.write(Data("wayline-daemon root olarak çalışmalı\n".utf8))
    exit(1)
}

signal(SIGPIPE, SIG_IGN)
let engine = Engine()
let server = Server(engine: engine)

let signalSources = [SIGTERM, SIGINT].map { sig in
    signal(sig, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
    source.setEventHandler {
        engine.shutdown()
        server.stop()
        exit(0)
    }
    source.resume()
    return source
}

engine.start()
do {
    try server.start()
} catch {
    log("socket error: \(error)")
    exit(1)
}
log("wayline-daemon \(DaemonProtocol.version) ready")
dispatchMain()
