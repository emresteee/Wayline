#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUILD="$ROOT/build"
APP="$BUILD/Wayline.app"
WG_COMMIT=b3bc704ef0ee21a36298601a9e1e5ff90377ac52

if [ ! -d vendor/wireguard-go ]; then
	git clone -q https://git.zx2c4.com/wireguard-go vendor/wireguard-go
fi
git -C vendor/wireguard-go checkout -q "$WG_COMMIT"
mkdir -p .build/wg
for arch in arm64 amd64; do
	(cd vendor/wireguard-go && CGO_ENABLED=0 GOOS=darwin GOARCH=$arch go build -trimpath -ldflags="-s -w" -o "$ROOT/.build/wg/wireguard-go-$arch" .)
done

for arch in arm64 x86_64; do
	swift build -c release --arch $arch
done
BIN=.build/universal
mkdir -p "$BIN"
for product in Wayline wayline-daemon; do
	lipo -create .build/arm64-apple-macosx/release/$product .build/x86_64-apple-macosx/release/$product -output "$BIN/$product"
done

rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/Service"
cp "$BIN/Wayline" "$APP/Contents/MacOS/Wayline"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$BIN/wayline-daemon" "$APP/Contents/Resources/Service/wayline-daemon"
lipo -create .build/wg/wireguard-go-arm64 .build/wg/wireguard-go-amd64 -output "$APP/Contents/Resources/Service/wireguard-go"
cp Resources/Service/install.sh Resources/Service/uninstall.sh Resources/Service/app.wayline.daemon.plist "$APP/Contents/Resources/Service/"

swift scripts/make_icon.swift "$BUILD/AppIcon.iconset"
iconutil -c icns "$BUILD/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"

for f in "$APP/Contents/Resources/Service/wireguard-go" "$APP/Contents/Resources/Service/wayline-daemon"; do
	codesign --force --sign - --options runtime "$f"
done
codesign --force --sign - --identifier app.wayline.Wayline "$APP"

if [ ! -x .build/dmgvenv/bin/dmgbuild ]; then
	python3 -m venv .build/dmgvenv
	.build/dmgvenv/bin/pip install -q dmgbuild
fi
swift scripts/make_dmg_background.swift "$BUILD/background.png" 1
swift scripts/make_dmg_background.swift "$BUILD/background@2x.png" 2
tiffutil -cathidpicheck "$BUILD/background.png" "$BUILD/background@2x.png" -out "$BUILD/background.tiff" >/dev/null
.build/dmgvenv/bin/dmgbuild -s scripts/dmg_settings.py -D app="$APP" -D background="$BUILD/background.tiff" "Wayline" "$BUILD/Wayline.dmg"
rm -f "$BUILD"/background*.png "$BUILD/background.tiff"
rm -rf "$BUILD/AppIcon.iconset"

echo "Hazır: $BUILD/Wayline.dmg"
