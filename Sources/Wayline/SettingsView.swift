import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: TunnelStore
    @Environment(\.dismiss) private var dismiss
    @State private var confirmUninstall = false
    var height: CGFloat = 680

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.muted)
                Text(L("Ayarlar", "Settings")).font(Theme.display(19))
                Spacer()
                Button(L("Bitti", "Done")) { dismiss() }
                    .buttonStyle(AccentButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .frame(height: 64)
            Rectangle().fill(Theme.stroke).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    protection.fadeIn(delay: 0.04)
                    wifi.fadeIn(delay: 0.10)
                    general.fadeIn(delay: 0.16)
                    service.fadeIn(delay: 0.22)
                }
                .padding(24)
            }
        }
        .frame(width: 640, height: height)
        .foregroundStyle(Theme.text)
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .toggleStyle(.switch)
        .tint(Theme.mint)
        .alert(L("Bir sorun oluştu", "Something went wrong"), isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button(L("Tamam", "OK"), role: .cancel) {}
        } message: {
            Text(store.errorMessage ?? "")
        }
        .alert(L("Servis kaldırılsın mı?", "Uninstall the service?"), isPresented: $confirmUninstall) {
            Button(L("Kaldır", "Uninstall"), role: .destructive) {
                dismiss()
                Task { await store.uninstallService() }
            }
            Button(L("Vazgeç", "Cancel"), role: .cancel) {}
        } message: {
            Text(L("Açık tünel kapanır ve kill switch kuralları silinir. Tünellerin bu Mac'te kalır; Wayline'ı tekrar kullanmak için servisi yeniden kurman gerekir.",
                   "Any open tunnel is closed and kill switch rules are removed. Your tunnels stay on this Mac; to use Wayline again you'll need to reinstall the service."))
        }
    }

    private var protection: some View {
        SettingsGroup(title: L("Koruma", "Protection")) {
            SettingRow(icon: "arrow.triangle.2.circlepath",
                       title: L("Bağlantı koruması", "Connection guard"),
                       detail: L("Tünel koptuğunda ya da ağ değiştiğinde bağlantıyı kendiliğinden yeniden kurar. Servis tarafında çalışır; uygulama kapalıyken de devam eder.",
                                 "Re-establishes the tunnel on its own when it drops or your network changes. Runs in the service, so it keeps working even with the app closed.")) {
                Toggle("", isOn: $store.watchdogEnabled).labelsHidden()
            }
            GroupDivider()
            SettingRow(icon: "lock.shield",
                       title: "Kill switch",
                       detail: L("Tünel düşerse tüm internet trafiğini engeller; böylece gerçek IP adresin hiçbir an açığa çıkmaz. Bağlantı geri gelince trafik yeniden akar.",
                                 "Blocks all internet traffic if the tunnel drops, so your real IP address never leaks, not even for a moment. Traffic flows again once the tunnel is back.")) {
                Toggle("", isOn: $store.killSwitch).labelsHidden()
            }
            SettingRow(icon: "printer",
                       title: L("Yerel ağa izin ver", "Allow local network"),
                       detail: L("Kill switch açıkken bile yazıcı, NAS ve AirDrop gibi yerel ağdaki cihazlara erişebilirsin.",
                                 "Keeps printers, NAS drives and AirDrop on your local network reachable while the kill switch is on."),
                       indented: true) {
                Toggle("", isOn: $store.allowLAN).labelsHidden()
            }
            .disabled(!store.killSwitch)
            .opacity(store.killSwitch ? 1 : 0.45)
            .animation(.easeInOut(duration: 0.3), value: store.killSwitch)
        }
    }

    private var wifi: some View {
        SettingsGroup(title: "Wi-Fi") {
            SettingRow(icon: "wifi",
                       title: L("Wi-Fi'de otomatik bağlan", "Auto-connect on Wi-Fi"),
                       detail: L("Kafe, otel ya da havaalanı gibi güvenmediğin bir ağa girdiğinde tüneli kendiliğinden açar. Ev ve iş gibi güvendiğin ağları aşağıya ekle.",
                                 "Turns the tunnel on by itself when you join a network you don't trust, like a café, hotel or airport. Add networks you trust, such as home or work, below.")) {
                Toggle("", isOn: $store.autoConnect).labelsHidden()
            }

            if store.wifiPermission != .granted {
                GroupDivider()
                permissionNote
            }

            GroupDivider()
            currentNetwork
            if !store.trustedNetworks.isEmpty {
                trustedList
            }
            GroupDivider()
            SettingRow(icon: "wifi.slash",
                       title: L("Güvenilen ağda bağlantıyı kes", "Disconnect on trusted networks"),
                       detail: L("Güvendiğin bir ağa döndüğünde tünel kendiliğinden kapanır.",
                                 "The tunnel turns off by itself when you're back on a network you trust.")) {
                Toggle("", isOn: $store.disconnectOnTrusted).labelsHidden()
            }
            GroupDivider()
            SettingRow(icon: "point.topleft.down.to.point.bottomright.curvepath",
                       title: L("Otomatik açılan tünel", "Tunnel to turn on"),
                       detail: L("Güvenilmeyen bir ağda hangi tünelin açılacağı.",
                                 "Which tunnel is turned on when you're on an untrusted network.")) {
                Picker("", selection: $store.autoConnectTunnel) {
                    Text(L("Seçili tünel", "Selected tunnel")).tag(String?.none)
                    if !store.tunnels.isEmpty { Divider() }
                    ForEach(store.tunnels, id: \.self) { Text($0).tag(Optional($0)) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
        }
    }

    private var permissionNote: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "location.circle")
                .font(.system(size: 15))
                .foregroundStyle(Theme.amber)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Wi-Fi adını görmek için izin gerekli", "Permission needed to see the Wi-Fi name"))
                    .font(.system(size: 12.5, weight: .semibold))
                Text(L("macOS, bağlı olduğun Wi-Fi ağının adını yalnızca konum izni olan uygulamalara gösterir. Wayline bu izni sadece ağ adını okumak için ister; konumun hiçbir zaman kullanılmaz ya da saklanmaz.",
                       "macOS only reveals the name of your Wi-Fi network to apps with location permission. Wayline asks for it solely to read the network name; your location is never used or stored."))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button(store.wifiPermission == .denied ? L("Sistem Ayarları'nda izin ver", "Allow in System Settings")
                                                       : L("İzin ver", "Grant permission")) {
                    store.requestWiFiPermission()
                }
                .buttonStyle(QuietButtonStyle(tint: Theme.amber))
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
    }

    private var currentNetwork: some View {
        let ssid = store.currentSSID
        let trusted = ssid.map { store.trustedNetworks.contains($0) } ?? false
        return HStack(spacing: 12) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(L("Şu anki ağ", "Current network"))
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.muted)
                Text(ssid ?? (store.wifiPermission == .granted ? L("Wi-Fi'ye bağlı değil", "Not on Wi-Fi") : L("Bilinmiyor", "Unknown")))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ssid == nil ? Theme.faint : Theme.text)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Group {
                if trusted {
                    Label(L("Güveniliyor", "Trusted"), systemImage: "checkmark.seal.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.mint)
                } else {
                    Button(L("Bu ağa güven", "Trust this network")) { store.trustCurrentNetwork() }
                        .buttonStyle(QuietButtonStyle())
                        .disabled(ssid == nil)
                        .opacity(ssid == nil ? 0.45 : 1)
                }
            }
            .frame(width: 170, alignment: .trailing)
        }
        .frame(height: 52)
    }

    private var trustedList: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Güvenilen ağlar", "Trusted networks"))
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.muted)
            FlowRow(items: store.trustedNetworks) { ssid in
                HStack(spacing: 6) {
                    Image(systemName: "house").font(.system(size: 10)).foregroundStyle(Theme.mint)
                    Text(ssid).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Button {
                        store.removeTrustedNetwork(ssid)
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(Theme.muted)
                            .frame(width: 16, height: 16)
                            .background(Theme.background.opacity(0.6), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help(L("Listeden çıkar", "Remove from list"))
                }
                .padding(.leading, 10).padding(.trailing, 5)
                .frame(height: 26)
                .background(Theme.panelRaised, in: Capsule())
                .overlay(Capsule().strokeBorder(Theme.stroke))
            }
        }
        .padding(.leading, 38)
        .padding(.bottom, 12)
    }

    private var general: some View {
        SettingsGroup(title: L("Genel", "General")) {
            SettingRow(icon: "bell",
                       title: L("Bildirimler", "Notifications"),
                       detail: L("Tünel bağlandığında, koptuğunda ya da güvenilmeyen bir ağda kendiliğinden açıldığında haber verir.",
                                 "Lets you know when the tunnel connects, drops, or turns on by itself on an untrusted network.")) {
                Toggle("", isOn: $store.notificationsEnabled).labelsHidden()
            }
            GroupDivider()
            SettingRow(icon: "command",
                       title: L("Klavye kısayolu", "Keyboard shortcut"),
                       detail: L("Hangi uygulamada olursan ol, bu tuşlarla tüneli açıp kapatırsın.",
                                 "Turn the tunnel on or off with these keys, from any app.")) {
                HStack(spacing: 10) {
                    Text(store.hotkeyLabel)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(store.hotkeyEnabled ? Theme.text : Theme.faint)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(Theme.panelRaised, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.strokeStrong))
                    Toggle("", isOn: $store.hotkeyEnabled).labelsHidden()
                }
            }
            GroupDivider()
            SettingRow(icon: "power",
                       title: L("Girişte başlat", "Launch at login"),
                       detail: L("Mac açıldığında Wayline menü çubuğunda sessizce başlar.",
                                 "Wayline starts quietly in the menu bar when you log in.")) {
                Toggle("", isOn: $store.launchAtLogin).labelsHidden()
            }
            GroupDivider()
            SettingRow(icon: "globe",
                       title: L("Dil", "Language"),
                       detail: L("Sistem seçiliyse macOS'un dili kullanılır.",
                                 "With System, Wayline follows your macOS language.")) {
                Picker("", selection: $store.language) {
                    ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
        }
    }

    private var service: some View {
        SettingsGroup(title: L("Servis", "Service")) {
            SettingRow(icon: "shippingbox",
                       title: L("Wayline servisi", "Wayline service"),
                       detail: L("Tüneli kuran, rotaları, DNS'i ve kill switch'i yöneten arka plan servisi. Wayline'ı bırakacaksan buradan kaldırabilirsin.",
                                 "The background service that creates the tunnel and manages routes, DNS and the kill switch. Remove it here if you stop using Wayline.")) {
                Button(L("Servisi kaldır…", "Uninstall…")) { confirmUninstall = true }
                    .buttonStyle(QuietButtonStyle(tint: Theme.rose))
            }
        }
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: title).padding(.leading, 4)
            VStack(alignment: .leading, spacing: 0) { content }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.stroke))
        }
    }
}

struct GroupDivider: View {
    var body: some View {
        Rectangle().fill(Theme.stroke).frame(height: 1).padding(.leading, 38)
    }
}

struct SettingRow<Control: View>: View {
    let icon: String
    let title: String
    let detail: String
    var indented = false
    @ViewBuilder var control: Control

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.mint)
                .frame(width: 26, height: 26)
                .background(Theme.mint.opacity(0.09), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .frame(height: 18, alignment: .leading)
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.muted)
                    .lineSpacing(1.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            control
                .frame(minWidth: 52, alignment: .trailing)
                .frame(height: 26)
        }
        .padding(.leading, indented ? 38 : 0)
        .padding(.vertical, 12)
    }
}

struct FlowRow<Item: Hashable, Cell: View>: View {
    let items: [Item]
    @ViewBuilder var cell: (Item) -> Cell

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { cell($0) }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 400
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > width { x = 0; y += row + spacing; row = 0 }
            x += s.width + spacing
            row = max(row, s.height)
        }
        return CGSize(width: width, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, row: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + s.width > bounds.maxX { x = bounds.minX; y += row + spacing; row = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            row = max(row, s.height)
        }
    }
}
