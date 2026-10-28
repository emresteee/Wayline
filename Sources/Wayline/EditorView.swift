import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WaylineCore

struct EditorView: View {
    @EnvironmentObject private var store: TunnelStore
    @Environment(\.dismiss) private var dismiss

    let target: EditorTarget

    @State private var name = ""
    @State private var text = ""
    @State private var loaded = false
    @State private var saveError: String?
    @State private var pickingQR = false
    @State private var copied = false

    private var originalName: String? {
        if case .edit(let n) = target { return n }
        return nil
    }

    var body: some View {
        let validation = Validation(text: text)

        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.stroke).frame(height: 1)

            VStack(alignment: .leading, spacing: 14) {
                nameField
                editor
                status(validation)
                publicKeyRow
            }
            .padding(24)

            Rectangle().fill(Theme.stroke).frame(height: 1)
            footer(validation)
        }
        .frame(width: 680, height: 640)
        .foregroundStyle(Theme.text)
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .onAppear(perform: load)
        .onChange(of: text) { saveError = nil }
        .onChange(of: name) { saveError = nil }
        .fileImporter(isPresented: $pickingQR, allowedContentTypes: [.image]) { result in
            guard case .success(let url) = result else { return }
            importQR(url)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: originalName == nil ? "plus.circle" : "slider.horizontal.3")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.muted)
            VStack(alignment: .leading, spacing: 1) {
                Text(originalName == nil ? L("Yeni tünel", "New tunnel") : L("Tüneli düzenle", "Edit tunnel"))
                    .font(Theme.display(19))
                Text(originalName == nil
                     ? L("Taze bir anahtar çifti hazır; sunucunun bilgilerini [Peer] bölümüne gir.",
                         "A fresh key pair is ready; fill in your server's details under [Peer].")
                     : L("Değişiklikler kaydedilince açık tünel yeni ayarlarla yeniden kurulur.",
                         "When you save, an open tunnel is rebuilt with the new settings."))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .frame(height: 68)
    }

    private var nameField: some View {
        HStack(spacing: 12) {
            Text(L("Ad", "Name"))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.muted)
                .frame(width: 44, alignment: .leading)
            TextField(L("ör. ev-ofis", "e.g. home-office"), text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.strokeStrong))
        }
    }

    private var editor: some View {
        TextEditor(text: $text)
            .font(.system(size: 12.5, design: .monospaced))
            .scrollContentBackground(.hidden)
            .autocorrectionDisabled()
            .padding(10)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.strokeStrong))
            .frame(maxHeight: .infinity)
    }

    private func status(_ v: Validation) -> some View {
        HStack(spacing: 8) {
            Image(systemName: v.error == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 12))
            Text(saveError ?? v.message)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .foregroundStyle(saveError != nil ? Theme.rose : (v.error == nil ? Theme.mint : Theme.amber))
        .frame(height: 18)
        .animation(.easeInOut(duration: 0.3), value: v.error == nil)
    }

    private var publicKeyRow: some View {
        let key = Validation.publicKey(in: text)
        return HStack(spacing: 10) {
            Text(L("Açık anahtar", "Public key"))
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.muted)
                .frame(width: 92, alignment: .leading)
            Text(key ?? "—")
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .foregroundStyle(key == nil ? Theme.faint : Theme.text)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 8)
            Button {
                guard let key else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(key, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { copied = false }
            } label: {
                Label(copied ? L("Kopyalandı", "Copied") : L("Kopyala", "Copy"),
                      systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(copied ? Theme.mint : Theme.muted)
                    .frame(width: 104, alignment: .trailing)
                    .animation(.easeInOut(duration: 0.3), value: copied)
            }
            .buttonStyle(.plain)
            .disabled(key == nil)
            .help(L("Bu anahtarı sunucuya eklemen gerekir", "Add this key to your server"))
        }
        .frame(height: 30)
        .padding(.horizontal, 12)
        .background(Theme.panel.opacity(0.7), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func footer(_ v: Validation) -> some View {
        HStack(spacing: 10) {
            Button {
                regenerateKeys()
            } label: {
                Label(L("Yeni anahtar üret", "Generate keys"), systemImage: "key")
            }
            .buttonStyle(QuietButtonStyle())
            .help(L("PrivateKey satırını yeni bir anahtarla değiştirir", "Replaces the PrivateKey line with a new key"))

            Button {
                pickingQR = true
            } label: {
                Label(L("QR'dan içe aktar", "Import from QR"), systemImage: "qrcode.viewfinder")
            }
            .buttonStyle(QuietButtonStyle())
            .help(L("Sağlayıcının verdiği QR kodu görselinden yapılandırmayı okur", "Reads the configuration from a QR code image your provider gave you"))

            Spacer()

            Button(L("Vazgeç", "Cancel")) { dismiss() }
                .buttonStyle(QuietButtonStyle(tint: Theme.muted))
                .keyboardShortcut(.cancelAction)
            Button(L("Kaydet", "Save")) { save() }
                .buttonStyle(AccentButtonStyle())
                .keyboardShortcut("s", modifiers: .command)
                .disabled(v.error != nil || name.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(v.error != nil || name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.45 : 1)
                .animation(.easeInOut(duration: 0.3), value: v.error == nil)
        }
        .padding(.horizontal, 24)
        .frame(height: 64)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        switch target {
        case .new:
            name = TunnelNames.suggestion(excluding: store.tunnels)
            text = store.newTunnelTemplate()
        case .edit(let n):
            name = n
            text = store.configText(for: n) ?? ""
        }
    }

    private func save() {
        do {
            try store.saveConfig(name: name, text: text, originalName: originalName)
            dismiss()
        } catch let error as WGConfig.ParseError {
            saveError = L(error.tr, error.en)
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func regenerateKeys() {
        let keys = store.generateKeyPair()
        text = Validation.replacingPrivateKey(in: text, with: keys)
        saveError = nil
    }

    private func importQR(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let payloads = QRImport.payloads(in: url)
        guard let payload = payloads.first(where: { (try? WGConfig.parse($0)) != nil }) ?? payloads.first else {
            saveError = L("Görselde WireGuard QR kodu bulunamadı", "No WireGuard QR code found in the image")
            return
        }
        text = payload
        saveError = nil
        if originalName == nil {
            let base = url.deletingPathExtension().lastPathComponent
            if !base.isEmpty { name = base }
        }
    }
}

private struct Validation {
    let config: WGConfig?
    let error: String?

    init(text: String) {
        do {
            config = try WGConfig.parse(text)
            error = nil
        } catch let e as WGConfig.ParseError {
            config = nil
            error = L(e.tr, e.en)
        } catch {
            config = nil
            self.error = error.localizedDescription
        }
    }

    var message: String {
        if let error { return error }
        guard let config else { return "" }
        let peers = config.peers.count
        let peerText = L("\(peers) eş", peers == 1 ? "1 peer" : "\(peers) peers")
        let route = config.isFullTunnel ? L("tüm trafik tünelden", "all traffic through the tunnel")
                                        : L("yalnızca seçili ağlar", "selected networks only")
        return L("Geçerli yapılandırma · \(peerText) · \(route)", "Valid configuration · \(peerText) · \(route)")
    }

    static func publicKey(in text: String) -> String? {
        for line in text.components(separatedBy: .newlines) {
            let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2, parts[0].lowercased() == "privatekey" else { continue }
            return WGKey.publicKey(fromPrivate: parts[1])
        }
        return nil
    }

    static func replacingPrivateKey(in text: String, with keys: (privateKey: String, publicKey: String)) -> String {
        var lines = text.components(separatedBy: "\n")
        var replaced = false
        for i in lines.indices {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            let key = trimmed.split(separator: "=", maxSplits: 1).first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            if key == "privatekey" {
                lines[i] = "PrivateKey = \(keys.privateKey)"
                replaced = true
            } else if trimmed.hasPrefix("#"), trimmed.contains("Açık anahtar:") || trimmed.contains("Public key:") {
                lines[i] = "# \(L("Açık anahtar", "Public key")): \(keys.publicKey)"
            }
        }
        if !replaced {
            if let i = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).lowercased() == "[interface]" }) {
                lines.insert("PrivateKey = \(keys.privateKey)", at: i + 1)
            } else {
                lines.insert(contentsOf: ["[Interface]", "PrivateKey = \(keys.privateKey)"], at: 0)
            }
        }
        return lines.joined(separator: "\n")
    }
}

enum TunnelNames {
    static func suggestion(excluding taken: [String]) -> String {
        let lower = Set(taken.map { $0.lowercased() })
        if !lower.contains("wayline") { return "wayline" }
        var n = 2
        while lower.contains("wayline-\(n)") { n += 1 }
        return "wayline-\(n)"
    }
}
