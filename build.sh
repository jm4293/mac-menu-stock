#!/bin/bash
# Bar 빌드 스크립트 — main.swift 를 컴파일해 Bar.app 번들 생성 (아이콘 포함)
set -e

APP_NAME="menu"
BUNDLE_ID="com.pyunhanga.menu"
DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$DIR/build"
APP="$BUILD_DIR/$APP_NAME.app"

# swiftc 존재 확인
if ! command -v swiftc >/dev/null 2>&1; then
  echo "❌ swiftc 가 없습니다. 먼저 Xcode Command Line Tools 를 설치하세요:"
  echo "   xcode-select --install"
  exit 1
fi

echo "▶︎ 빌드 중..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

# 컴파일
swiftc -O -o "$APP/Contents/MacOS/$APP_NAME" "$DIR/main.swift" -framework Cocoa

# 아이콘 생성 (icon.png → AppIcon.icns)  ※ sips/iconutil 은 macOS 기본 제공
HAS_ICON="false"
if [ -f "$DIR/icon.png" ]; then
  ICONSET="$BUILD_DIR/AppIcon.iconset"
  rm -rf "$ICONSET"; mkdir -p "$ICONSET"
  sips -z 16 16     "$DIR/icon.png" --out "$ICONSET/icon_16x16.png"      >/dev/null
  sips -z 32 32     "$DIR/icon.png" --out "$ICONSET/icon_16x16@2x.png"   >/dev/null
  sips -z 32 32     "$DIR/icon.png" --out "$ICONSET/icon_32x32.png"      >/dev/null
  sips -z 64 64     "$DIR/icon.png" --out "$ICONSET/icon_32x32@2x.png"   >/dev/null
  sips -z 128 128   "$DIR/icon.png" --out "$ICONSET/icon_128x128.png"    >/dev/null
  sips -z 256 256   "$DIR/icon.png" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
  sips -z 256 256   "$DIR/icon.png" --out "$ICONSET/icon_256x256.png"    >/dev/null
  sips -z 512 512   "$DIR/icon.png" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
  sips -z 512 512   "$DIR/icon.png" --out "$ICONSET/icon_512x512.png"    >/dev/null
  sips -z 1024 1024 "$DIR/icon.png" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
  rm -rf "$ICONSET"
  HAS_ICON="true"
  echo "🎨 아이콘 적용됨"
fi

# Info.plist (LSUIElement=true → Dock 아이콘 없이 메뉴바에만 표시)
ICON_KEY=""
if [ "$HAS_ICON" = "true" ]; then
  ICON_KEY="    <key>CFBundleIconFile</key>        <string>AppIcon</string>"
fi

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>     <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>      <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>      <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>         <string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
$ICON_KEY
    <key>LSMinimumSystemVersion</key>  <string>12.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSHighResolutionCapable</key> <true/>
</dict>
</plist>
EOF

echo "✅ 완료: $APP"
echo ""
echo "실행:  open \"$APP\""
echo "설치:  cp -R \"$APP\" /Applications/   (그 후 응용프로그램에서 실행)"
