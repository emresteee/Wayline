import AppKit
import Carbon.HIToolbox
import UserNotifications
import Vision

enum Notifier {
    static func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func post(_ title: String, _ body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

final class HotKey {
    static let shared = HotKey()
    static let label = "⌃⌥⌘W"

    var handler: (() -> Void)?
    private var ref: EventHotKeyRef?
    private var installed = false

    func register() {
        guard ref == nil else { return }
        if !installed {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { HotKey.shared.handler?() }
                return noErr
            }, 1, &type, nil, nil)
            installed = true
        }
        let id = EventHotKeyID(signature: OSType(0x57594C4E), id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_W), UInt32(controlKey | optionKey | cmdKey), id,
                            GetApplicationEventTarget(), 0, &ref)
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }
}

enum QRImport {
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "heic", "tiff", "gif", "bmp", "webp"]

    static func payloads(in url: URL) -> [String] {
        guard let image = NSImage(contentsOf: url),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return [] }
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        try? VNImageRequestHandler(cgImage: cg).perform([request])
        return (request.results ?? []).compactMap(\.payloadStringValue)
    }
}
