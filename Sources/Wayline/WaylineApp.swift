import AppKit
import SwiftUI

@main
struct WaylineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = TunnelStore()

    var body: some Scene {
        Window("Wayline", id: "main") {
            ContentView().environmentObject(store)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarView().environmentObject(store)
        } label: {
            Image(nsImage: WaylineMark.menuBarImage(connected: store.status == .connected,
                                                    transitioning: store.status.isTransitioning))
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillFinishLaunching(_ notification: Notification) {
        MoveToApplications.requireApplicationsFolder()
    }
}
