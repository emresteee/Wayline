import SwiftUI

struct SetupView: View {
    @EnvironmentObject private var store: TunnelStore

    private var outdated: Bool { store.setup == .serviceOutdated }

    var body: some View {
        ZStack {
            RouteMap(home: nil, server: nil, status: .disconnected, showsLabels: false)
                .opacity(0.55)
            AuroraBackground(status: store.installing ? .connecting : .disconnected)
                .opacity(0.9)
            LinearGradient(colors: [Theme.background.opacity(0.2), Theme.background], startPoint: .top, endPoint: .bottom)

            VStack(spacing: 0) {
                WaylineMark(color: store.installing ? Theme.amber : Theme.mint, size: 60)
                    .animation(.easeInOut(duration: 0.8), value: store.installing)
                    .padding(.bottom, 22)

                Text(outdated ? L("Wayline servisi güncellenmeli", "The Wayline service needs an update")
                              : L("Wayline'a hoş geldin", "Welcome to Wayline"))
                    .font(Theme.display(26))
                    .lineLimit(1)
                    .frame(height: 34)
                    .padding(.bottom, 10)

                Text(outdated
                     ? L("Uygulama güncellendi; arka plan servisinin de yeni sürüme geçmesi gerekiyor. Yönetici parolan bir kez sorulur, tünellerin ve ayarların korunur.",
                         "The app was updated, so its background service needs to move to the new version too. Your admin password is asked once; tunnels and settings are kept.")
                     : L("Wayline, tüneli kuran küçük bir arka plan servisiyle çalışır. Servis yalnızca bir kez kurulur ve bunun için yönetici parolan bir kez sorulur.",
                         "Wayline runs a small background service that creates the tunnel. It's installed only once, and your admin password is asked just that one time."))
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .frame(width: 470, height: 56, alignment: .top)
                    .padding(.bottom, 26)

                HStack(spacing: 12) {
                    point("lock.shield", L("Tüneli o kurar", "Creates the tunnel"),
                          L("Rotalar, DNS ve kill switch", "Routes, DNS and kill switch"))
                    point("arrow.triangle.2.circlepath", L("Arka planda korur", "Guards in background"),
                          L("Uygulama kapalıyken de", "Even when the app is closed"))
                    point("person.badge.key", L("Tek seferlik izin", "One-time permission"),
                          L("Sonra parola sorulmaz", "No password prompts after"))
                }
                .padding(.bottom, 30)

                Button {
                    Task { await store.installService() }
                } label: {
                    HStack(spacing: 9) {
                        ZStack {
                            ProgressView().controlSize(.small).tint(.black)
                                .opacity(store.installing ? 1 : 0)
                            Image(systemName: outdated ? "arrow.down.circle" : "checkmark.shield")
                                .opacity(store.installing ? 0 : 1)
                        }
                        .frame(width: 16, height: 16)
                        Text(buttonTitle)
                            .lineLimit(1)
                    }
                    .frame(width: 190)
                }
                .buttonStyle(AccentButtonStyle())
                .disabled(store.installing)
                .animation(.easeInOut(duration: 0.3), value: store.installing)

                Text(store.installing ? L("Sistem parolanı bekliyor olabilir…", "macOS may be waiting for your password…") : " ")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.faint)
                    .frame(height: 16)
                    .padding(.top, 12)
                    .animation(.easeInOut(duration: 0.4), value: store.installing)
            }
            .padding(40)
            .fadeIn(delay: 0.1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var buttonTitle: String {
        if store.installing { return outdated ? L("Güncelleniyor…", "Updating…") : L("Kuruluyor…", "Installing…") }
        return outdated ? L("Servisi güncelle", "Update service") : L("Servisi kur", "Install service")
    }

    private func point(_ icon: String, _ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.mint)
                .frame(height: 18)
            Text(title)
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(1)
            Text(detail)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.muted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(width: 172, height: 104, alignment: .topLeading)
        .background(Theme.panel.opacity(0.85), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.stroke))
    }
}
