<div align="center">

# Wayline

**A WireGuard client for macOS with its own tunnel engine.**

Wayline connects your Mac to any WireGuard server. It does not need the official WireGuard app. The tunnel keeps running even when the app is closed.

**English** · [Türkçe](README.tr.md)

![Wayline main window](docs/screenshots/en-main.png)

</div>

## What it does

WireGuard is a fast, modern VPN protocol. Your VPN provider or your own server gives you a `.conf` file. Wayline turns that file into a working tunnel with one click.

When the tunnel is on, all of your traffic leaves through the server: websites see the server's IP address instead of yours. Wayline shows you exactly where your traffic goes, how fast it is moving, and what happens to the connection over time.

## Features

### Connection

- **Own engine.** `wireguard-go` is built into the app, and a small system service manages the tunnel, routes and DNS. The official WireGuard app is not needed.
- **Fast connect.** A tunnel is up in about 70 ms. The first handshake completes in under 100 ms on a typical connection.
- **Stays up without the app.** The service keeps the tunnel open when the window is closed or the app quits, and brings it back after a restart.
- **Connection guard.** If the server stops answering, Wayline renews the handshake without dropping the tunnel. If that does not help, it rebuilds the tunnel, waiting a little longer between attempts each time (5 s up to 120 s). When you switch between Wi-Fi and Ethernet, it moves the connection to the new network.

### Protection

- **Kill switch.** If the tunnel drops, all internet traffic is blocked, so your real IP address never leaks, not even for a moment.
- **Allow local network.** Printers, NAS drives and AirDrop stay reachable while the kill switch is on.

### Wi-Fi

- **Auto-connect on untrusted Wi-Fi.** Wayline turns the tunnel on by itself when you join a café, hotel or airport network.
- **Trusted networks.** Mark home or work as trusted, and the tunnel can turn itself off when you are back.
- **Choose the tunnel** that opens automatically.

macOS only shows Wi-Fi names to apps with location permission. Wayline asks for it only to read the network name, and never stores or sends your location.

### Tunnels

- **Import** a `.conf` file or an image of a WireGuard QR code, by dragging it onto the window or using **Add tunnel**.
- **Edit** configurations with live validation. Mistakes are shown while you type.
- **Create** a tunnel from scratch with a freshly generated key pair, and copy the public key for your server.
- **Export** any tunnel back to a `.conf` file.

### Everyday use

- **Live route map** from your location to the server, with the address the internet sees.
- **Traffic, latency and session** cards with the last two minutes of history, plus an event log of everything that happened to the connection.
- **Menu bar panel** to check status and switch tunnels without opening the window.
- **Notifications** when the tunnel connects, drops or turns on automatically.
- **Global shortcut** ⌃⌥⌘W to connect or disconnect from any app.
- **Launch at login**, plus **English and Turkish**, following your system language by default.

## Screenshots

<table>
  <tr>
    <td width="33%"><img src="docs/screenshots/en-menubar.png" alt="Menu bar panel"></td>
    <td width="67%"><img src="docs/screenshots/en-settings.png" alt="Settings"></td>
  </tr>
  <tr>
    <td>Menu bar panel</td>
    <td>Settings: every option explains what it does</td>
  </tr>
</table>

<img src="docs/screenshots/en-editor.png" alt="Configuration editor" width="70%">

Configuration editor with live validation, key generation and QR import.

All screenshots use example data: the locations, addresses and keys are not real.

## Install

1. Download `Wayline.dmg` from [Releases](https://github.com/emresteee/Wayline/releases) and drag **Wayline** into **Applications**.
2. The app is not notarized by Apple yet. The first time, right-click Wayline in Applications and choose **Open**.
3. Wayline asks for your administrator password once to install its service. After that, no password is needed.

Requirements: macOS 14 Sonoma or later, Apple Silicon or Intel.

### Uninstall

Open **Settings › Service › Uninstall…** in the app, or run:

```sh
sudo bash /Applications/Wayline.app/Contents/Resources/Service/uninstall.sh
```

Then move Wayline to the Trash. Your tunnels are kept in `~/Library/Application Support/Wayline` until you delete that folder.

## Privacy and security

- Tunnel configurations, including private keys, stay on your Mac in `~/Library/Application Support/Wayline/Tunnels` with owner-only permissions.
- The service only accepts requests from root, the user who installed it, and administrators. Every connection is checked by the system.
- To show the map, Wayline looks up the location of your public IP and the server's IP at `ipinfo.io`. Nothing else leaves your Mac, and there is no analytics or telemetry.

## Build from source

Requirements: macOS 14+, Command Line Tools (Xcode is not required), Go (`brew install go`) and Python 3.

```sh
git clone https://github.com/emresteee/Wayline.git
cd Wayline
./scripts/build.sh
```

The script creates `build/Wayline.app` and `build/Wayline.dmg` as a universal app. It:

1. Builds `wireguard-go` from a pinned commit for Apple Silicon and Intel.
2. Builds the Swift targets for both architectures and merges them with `lipo`.
3. Draws the app icon and signs the bundle ad hoc.
4. Packages the DMG with `dmgbuild`, which it installs into `.build/dmgvenv`.

## How it works

```
Wayline.app (you)  ── local socket ──▶  wayline-daemon (system service)
                                          ├─ wireguard-go   the WireGuard tunnel (utun)
                                          ├─ ifconfig/route addresses and routes
                                          ├─ configd        DNS while the tunnel is up
                                          └─ pf             kill switch rules
```

| Part | Folder | Role |
|---|---|---|
| `WaylineCore` | `Sources/WaylineCore` | Reads and writes `.conf` files, handles keys, defines the app ↔ service protocol |
| `Wayline` | `Sources/Wayline` | The SwiftUI app |
| `wayline-daemon` | `Sources/WaylineDaemon` | The system service: tunnel lifecycle, connection guard, routes, DNS, kill switch |

The service logs every connect and disconnect with timings to `/Library/Logs/Wayline/daemon.log`.

## Troubleshooting

| Problem | Check |
|---|---|
| Tunnel does not come up | `/Library/Logs/Wayline/daemon.log` |
| Websites do not load | DNS with `scutil --dns`, routes with `netstat -rn -f inet` |
| No internet after quitting | The kill switch may still be on. Turn it off in Settings, or run `sudo pfctl -a com.apple/250.Wayline -F rules` |

## License

[MIT](LICENSE). Wayline includes [wireguard-go](https://git.zx2c4.com/wireguard-go), which is also MIT licensed. WireGuard is a registered trademark of Jason A. Donenfeld. Wayline is not affiliated with the WireGuard project.
