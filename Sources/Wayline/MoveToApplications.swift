import AppKit

enum MoveToApplications {
    static var isInApplications: Bool {
        let bundle = Bundle.main.bundleURL.resolvingSymlinksInPath()
        return ["/Applications", NSHomeDirectory() + "/Applications"].contains { bundle.path.hasPrefix($0 + "/") }
    }

    static func requireApplicationsFolder() {
        guard !isInApplications else { return }
        let bundle = Bundle.main.bundleURL.resolvingSymlinksInPath()

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L("Applications klasörüne taşınsın mı?", "Move to the Applications folder?")
        alert.informativeText = L(
            "Wayline yalnızca Applications klasöründen çalışır. Kendini oraya taşıyıp yeniden açılır; diğer uygulamalar gibi Launchpad'de görünür.",
            "Wayline runs from your Applications folder. It will move itself there and reopen, and show up in Launchpad like any other app.")
        alert.addButton(withTitle: L("Applications'a taşı", "Move to Applications"))
        alert.addButton(withTitle: L("Çık", "Quit"))
        guard alert.runModal() == .alertFirstButtonReturn else {
            exit(0)
        }

        let destination = URL(fileURLWithPath: "/Applications/Wayline.app")
        do {
            try install(bundle, at: destination)
        } catch {
            let failure = NSAlert(error: error)
            failure.messageText = L("Taşınamadı", "Couldn't move Wayline")
            failure.runModal()
            exit(1)
        }
        relaunch(destination, ejecting: bundle)
    }

    private static func install(_ source: URL, at destination: URL) throws {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        where app.bundleURL?.resolvingSymlinksInPath() == destination.resolvingSymlinksInPath() {
            app.terminate()
        }
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.trashItem(at: destination, resultingItemURL: nil)
            }
            try FileManager.default.copyItem(at: source, to: destination)
        } catch {
            let target = ServiceClient.quoted(destination.path)
            let command = "rm -rf \(target) && /usr/bin/ditto \(ServiceClient.quoted(source.path)) \(target)"
            let script = "do shell script \(ServiceClient.appleScriptLiteral(command)) with administrator privileges"
            var errorInfo: NSDictionary?
            NSAppleScript(source: script)?.executeAndReturnError(&errorInfo)
            if errorInfo != nil { throw error }
        }
        _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/xattr"), arguments: ["-dr", "com.apple.quarantine", destination.path])
    }

    private static func relaunch(_ destination: URL, ejecting source: URL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        var script = "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \(ServiceClient.quoted(destination.path))"
        if source.path.hasPrefix("/Volumes/") {
            let volume = "/Volumes/" + source.path.dropFirst("/Volumes/".count).split(separator: "/")[0]
            script += "; /usr/bin/hdiutil detach -quiet \(ServiceClient.quoted(volume))"
        }
        _ = try? Process.run(URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", script])
        exit(0)
    }
}
