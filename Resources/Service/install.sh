#!/bin/bash
set -euo pipefail

SRC="${1:?Service klasörü}"
OWNER="${2:?uid}"
[[ "$OWNER" =~ ^[0-9]+$ ]] || { echo "Geçersiz uid" >&2; exit 1; }

DEST=/Library/PrivilegedHelperTools/app.wayline
PLIST=/Library/LaunchDaemons/app.wayline.daemon.plist
STATE="/Library/Application Support/Wayline"

launchctl bootout system/app.wayline.daemon 2>/dev/null || true

mkdir -p "$DEST" "$STATE" /Library/Logs/Wayline
install -o root -g wheel -m 755 "$SRC/wayline-daemon" "$DEST/wayline-daemon"
install -o root -g wheel -m 755 "$SRC/wireguard-go" "$DEST/wireguard-go"
install -o root -g wheel -m 644 "$SRC/app.wayline.daemon.plist" "$PLIST"
chown root:wheel "$STATE"
chmod 700 "$STATE"
echo "$OWNER" >"$STATE/owner"
chmod 600 "$STATE/owner"
xattr -cr "$DEST" 2>/dev/null || true

launchctl bootstrap system "$PLIST"
launchctl enable system/app.wayline.daemon
