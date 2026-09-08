#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Open VibeKey"
BUNDLE_ID="com.openvibekey.app"
VERSION="0.1.2"
BUILD_NUMBER="3"
MIN_MACOS="13.0"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PKG="$ROOT/native/VibeKit"
BUILD_DIR="$PKG/.build/release"
APP="$ROOT/dist/$APP_NAME.app"
ICON_SOURCE="$ROOT/assets/AppIcon.png"
if [ ! -f "$ICON_SOURCE" ]; then
  echo "缺少 App 图标：$ICON_SOURCE" >&2
  exit 1
fi

echo "==> 构建 release"
swift build -c release --package-path "$PKG"

echo "==> 组装 bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BUILD_DIR/VibeKitApp" "$APP/Contents/MacOS/VibeKitApp"

# App resource lookup uses Contents/Resources; this is also the only location
# accepted by macOS code signing for an application bundle.
for b in VibeKit_VibeKitCore.bundle VibeKit_VibeKitApp.bundle; do
  if [ ! -d "$BUILD_DIR/$b" ]; then
    echo "❌ 缺少资源包 $b（SwiftPM 布局变了？）" >&2
    exit 1
  fi
  cp -R "$BUILD_DIR/$b" "$APP/Contents/Resources/"
done

echo "==> 生成 App 图标"
ICONSET="$BUILD_DIR/OpenVibeKey.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  retina=$((size * 2))
  sips -z "$retina" "$retina" "$ICON_SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "==> 生成 Info.plist"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleExecutable</key><string>VibeKitApp</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key><string>用于显示 VibeKey 麦克风的实时输入电平。</string>
</dict>
</plist>
PLIST

echo "==> 签名"
ENTITLEMENTS="$ROOT/scripts/OpenVibeKey.entitlements"
if [ ! -f "$ENTITLEMENTS" ]; then
  echo "❌ 缺少 $ENTITLEMENTS —— 没有它签出来的包在 hardened runtime 下用不了麦克风" >&2
  exit 1
fi

if [ -n "${SIGN_IDENTITY:-}" ]; then
  codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" --sign "$SIGN_IDENTITY" "$APP"
  echo "    已用 $SIGN_IDENTITY 签名（hardened runtime + entitlements）"
else
  codesign --force --options runtime --entitlements "$ENTITLEMENTS" --sign - "$APP"
  echo "    未设 SIGN_IDENTITY，已对整个 bundle 做 ad-hoc 重签（hardened runtime + entitlements）。"
  echo "    代价：签名哈希每次重建都变，麦克风授权可能需重新点一次。"
fi
codesign --verify --strict "$APP"

echo "✅ $APP"
