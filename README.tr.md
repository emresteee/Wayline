<div align="center">

# Wayline

**Kendi tünel motoruyla çalışan macOS WireGuard istemcisi.**

Wayline, Mac'ini herhangi bir WireGuard sunucusuna bağlar. Resmi WireGuard uygulamasına ihtiyaç duymaz; uygulama kapalıyken de tünel açık kalır.

[English](README.md) · **Türkçe**

![Wayline ana pencere](docs/screenshots/tr-main.png)

</div>

## Ne işe yarar

WireGuard hızlı ve modern bir VPN protokolüdür. VPN sağlayıcın ya da kendi sunucun sana bir `.conf` dosyası verir. Wayline bu dosyayı tek tıkla çalışan bir tünele dönüştürür.

Tünel açıkken tüm trafiğin sunucu üzerinden çıkar; siteler senin IP adresini değil, sunucunun IP adresini görür. Wayline trafiğinin nereden çıktığını, ne hızda aktığını ve bağlantıda neler olduğunu açıkça gösterir.

## Özellikler

### Bağlantı

- **Kendi motoru:** `wireguard-go` uygulamanın içinde gelir. Tüneli, rotaları ve DNS'i küçük bir sistem servisi yönetir; resmi WireGuard uygulaması gerekmez.
- **Hızlı bağlanma:** tünel yaklaşık 70 ms'de kurulur, ilk el sıkışma tipik bir bağlantıda 100 ms'nin altında tamamlanır.
- **Uygulama olmadan da açık kalır:** pencereyi kapatsan ya da uygulamadan çıksan da servis tüneli açık tutar; Mac yeniden başladığında tünel geri gelir.
- **Bağlantı koruması:** sunucu yanıt vermeyi keserse Wayline tüneli kapatmadan el sıkışmayı yeniler. Bu yetmezse tüneli baştan kurar ve her denemede biraz daha uzun bekler (5 sn'den 120 sn'ye). Wi-Fi ile Ethernet arasında geçiş yaptığında bağlantıyı yeni ağa taşır.

### Koruma

- **Kill switch:** tünel düşerse tüm internet trafiği engellenir; gerçek IP adresin bir an bile açığa çıkmaz.
- **Yerel ağa izin ver:** kill switch açıkken bile yazıcı, NAS ve AirDrop gibi yerel ağdaki cihazlara erişebilirsin.

### Wi-Fi

- **Güvenilmeyen Wi-Fi'de otomatik bağlan:** kafe, otel ya da havaalanı ağına girdiğinde tünel kendiliğinden açılır.
- **Güvenilen ağlar:** evi ya da işi güvenilen olarak işaretlersen oraya döndüğünde tünel kendiliğinden kapanabilir.
- **Otomatik açılacak tüneli seç.**

macOS Wi-Fi adını yalnızca konum izni olan uygulamalara gösterir. Wayline bu izni yalnızca ağ adını okumak için ister; konumunu saklamaz ve hiçbir yere göndermez.

### Tüneller

- **İçe aktar:** bir `.conf` dosyasını ya da WireGuard QR kodu içeren bir görseli pencereye sürükle ya da **Tünel ekle**'yi kullan.
- **Düzenle:** yapılandırmayı canlı doğrulamayla düzenle; hatalar yazarken gösterilir.
- **Oluştur:** sıfırdan, yeni üretilmiş bir anahtar çiftiyle tünel oluştur ve açık anahtarı sunucun için kopyala.
- **Dışa aktar:** herhangi bir tüneli yeniden `.conf` dosyası olarak kaydet.

### Günlük kullanım

- **Canlı rota haritası:** konumundan sunucuya uzanan rota ve internetin gördüğü adres.
- **Trafik, gecikme ve oturum** kartları son iki dakikanın geçmişiyle; bağlantıda olan her şeyin yazıldığı bir olay günlüğü.
- **Menü çubuğu paneli:** pencereyi açmadan durumu gör ve tünel değiştir.
- **Bildirimler:** tünel bağlandığında, koptuğunda ya da kendiliğinden açıldığında haber verir.
- **Genel kısayol:** her uygulamadayken ⌃⌥⌘W ile bağlan ya da bağlantıyı kes.
- **Girişte başlatma**, ayrıca **Türkçe ve İngilizce** arayüz (varsayılan olarak sistem dilini izler).

## Ekran görüntüleri

<table>
  <tr>
    <td width="33%"><img src="docs/screenshots/tr-menubar.png" alt="Menü çubuğu paneli"></td>
    <td width="67%"><img src="docs/screenshots/tr-settings.png" alt="Ayarlar"></td>
  </tr>
  <tr>
    <td>Menü çubuğu paneli</td>
    <td>Ayarlar: her seçeneğin altında ne işe yaradığı yazar</td>
  </tr>
</table>

<img src="docs/screenshots/tr-editor.png" alt="Yapılandırma editörü" width="70%">

Canlı doğrulama, anahtar üretme ve QR'dan içe aktarma özellikli yapılandırma editörü.

Tüm ekran görüntülerinde örnek veriler kullanılmıştır: konumlar, adresler ve anahtarlar gerçek değildir.

## Kurulum

1. [Releases](https://github.com/emresteee/Wayline/releases) sayfasından `Wayline.dmg`'yi indir ve **Wayline**'ı **Applications** klasörüne sürükle.
2. Uygulama henüz Apple tarafından onaylanmadı (notarize edilmedi). İlk açılışta Applications'ta Wayline'a sağ tıklayıp **Aç**'ı seç.
3. Wayline servisini kurmak için bir kez yönetici şifreni ister; sonrasında şifre gerekmez.

Gereksinimler: macOS 14 Sonoma ya da daha yenisi, Apple Silicon ya da Intel.

### Kaldırma

Uygulamada **Ayarlar › Servis › Servisi kaldır…**'ı seç ya da şunu çalıştır:

```sh
sudo bash /Applications/Wayline.app/Contents/Resources/Service/uninstall.sh
```

Ardından Wayline'ı Çöp Sepeti'ne taşı. Tünellerin, `~/Library/Application Support/Wayline` klasörünü silene kadar Mac'inde kalır.

## Gizlilik ve güvenlik

- Özel anahtarlar dahil tünel yapılandırmaları Mac'inde, `~/Library/Application Support/Wayline/Tunnels` içinde yalnızca senin okuyabileceğin izinlerle durur.
- Servis yalnızca root'tan, servisi kuran kullanıcıdan ve yöneticilerden gelen istekleri kabul eder; her bağlantı sistem tarafından doğrulanır.
- Haritayı göstermek için Wayline, genel IP adresinin ve sunucunun IP adresinin konumunu `ipinfo.io`'dan sorgular. Bunun dışında Mac'inden hiçbir şey çıkmaz; analiz ya da telemetri yoktur.

## Kaynaktan derleme

Gereksinimler: macOS 14+, Command Line Tools (Xcode gerekmez), Go (`brew install go`) ve Python 3.

```sh
git clone https://github.com/emresteee/Wayline.git
cd Wayline
./scripts/build.sh
```

Betik universal bir uygulama olarak `build/Wayline.app` ve `build/Wayline.dmg` üretir. Sırasıyla:

1. `wireguard-go`'yu sabit bir commit'ten Apple Silicon ve Intel için derler.
2. Swift hedeflerini iki mimari için derleyip `lipo` ile birleştirir.
3. Uygulama simgesini çizer ve paketi ad-hoc imzalar.
4. DMG'yi `dmgbuild` ile paketler; `dmgbuild`'i `.build/dmgvenv` içine kendisi kurar.

## Nasıl çalışır

```
Wayline.app (sen)  ── yerel soket ──▶  wayline-daemon (sistem servisi)
                                         ├─ wireguard-go   WireGuard tüneli (utun)
                                         ├─ ifconfig/route adresler ve rotalar
                                         ├─ configd        tünel açıkken DNS
                                         └─ pf             kill switch kuralları
```

| Parça | Klasör | Görevi |
|---|---|---|
| `WaylineCore` | `Sources/WaylineCore` | `.conf` dosyalarını okur ve yazar, anahtarları işler, uygulama ↔ servis protokolünü tanımlar |
| `Wayline` | `Sources/Wayline` | SwiftUI uygulaması |
| `wayline-daemon` | `Sources/WaylineDaemon` | Sistem servisi: tünelin yaşam döngüsü, bağlantı koruması, rotalar, DNS, kill switch |

Servis her bağlanma ve kesmeyi süreleriyle birlikte `/Library/Logs/Wayline/daemon.log` dosyasına yazar.

## Sorun giderme

| Sorun | Bakılacak yer |
|---|---|
| Tünel açılmıyor | `/Library/Logs/Wayline/daemon.log` |
| Siteler açılmıyor | DNS için `scutil --dns`, rotalar için `netstat -rn -f inet` |
| Çıktıktan sonra internet yok | Kill switch hâlâ açık olabilir. Ayarlar'dan kapat ya da `sudo pfctl -a com.apple/250.Wayline -F rules` çalıştır |

## Lisans

[MIT](LICENSE). Wayline, yine MIT lisanslı olan [wireguard-go](https://git.zx2c4.com/wireguard-go)'yu içerir. WireGuard, Jason A. Donenfeld'in tescilli markasıdır; Wayline WireGuard projesiyle bağlantılı değildir.
