#!/usr/bin/env bash
set -euo pipefail

APP_NAME="VideoWallpaper"
APP_DIR="$PWD/${APP_NAME}.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RES="$CONTENTS/Resources"
PLIST="$CONTENTS/Info.plist"

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RES"

# Info.plist（无 Dock 图标，仅菜单栏）
cat > "$PLIST" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>local.videowallpaper2</string>
  <key>CFBundleName</key><string>VideoWallpaper</string>
  <key>CFBundleDisplayName</key><string>VideoWallpaper</string>
  <key>CFBundleVersion</key><string>1.0</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
  <key>LSUIElement</key><false/> <!-- 隐藏 Dock 图标，显示菜单栏 -->
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

# 编译可执行文件到 .app
swiftc -O -parse-as-library \
  -framework AppKit -framework AVFoundation -framework QuartzCore \
  VideoWallpaperApp.swift -o "$MACOS/$APP_NAME"

echo "Built app: $APP_DIR"
echo "可以用 Finder 双击运行，或："
echo "open \"$APP_DIR\""
