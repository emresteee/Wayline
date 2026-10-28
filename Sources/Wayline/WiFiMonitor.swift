import CoreLocation
import CoreWLAN
import Foundation

@MainActor
final class WiFiMonitor: NSObject, ObservableObject {
    enum Permission { case notAsked, denied, granted }

    @Published private(set) var ssid: String?
    @Published private(set) var permission: Permission = .notAsked

    var onChange: ((String?) -> Void)?

    private let location = CLLocationManager()
    private let client = CWWiFiClient.shared()

    override init() {
        super.init()
        location.delegate = self
        client.delegate = self
        try? client.startMonitoringEvent(with: .ssidDidChange)
        try? client.startMonitoringEvent(with: .linkDidChange)
        updatePermission()
        refresh()
    }

    func requestPermission() {
        location.requestWhenInUseAuthorization()
    }

    func refresh() {
        let current = client.interface()?.ssid()
        guard current != ssid else { return }
        ssid = current
        onChange?(current)
    }

    private func updatePermission() {
        switch location.authorizationStatus {
        case .authorizedAlways, .authorized: permission = .granted
        case .denied, .restricted: permission = .denied
        default: permission = .notAsked
        }
    }
}

extension WiFiMonitor: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            self.updatePermission()
            self.refresh()
        }
    }
}

extension WiFiMonitor: CWEventDelegate {
    nonisolated func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
        Task { @MainActor in self.refresh() }
    }

    nonisolated func linkDidChangeForWiFiInterface(withName interfaceName: String) {
        Task { @MainActor in self.refresh() }
    }
}
