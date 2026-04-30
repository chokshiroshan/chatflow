#!/bin/bash
set -e

# ChatFlow Full Build Pipeline
# Builds the Swift binary, creates .app bundle, and optionally creates DMG.
# Run on macOS 14+.
#
# Usage:
#   ./build.sh            — Build .app only
#   ./build.sh dmg        — Build .app + DMG installer
#   ./build.sh clean      — Clean build artifacts

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="ChatFlow"
BUNDLE_ID="ai.flow.app"
VERSION="1.0.0"
BUILD_NUM="1"
BINARY=".build/release/Flow"
APP_BUNDLE="build/${APP_NAME}.app"

# --- Helper functions (must be defined before use) ---

create_app_icon() {
    local output="$1"
    local iconset="/tmp/chatflow.iconset"
    rm -rf "$iconset"
    mkdir -p "$iconset"
    
    if command -v python3 &>/dev/null && python3 -c "from PIL import Image, ImageDraw" 2>/dev/null; then
        python3 - <<'PYTHON'
from PIL import Image, ImageDraw
import os

iconset = "/tmp/chatflow.iconset"
sizes = [16, 32, 64, 128, 256, 512]

for s in sizes:
    img = Image.new('RGBA', (s, s), (10, 15, 31, 255))
    draw = ImageDraw.Draw(img)
    
    margin = max(2, s // 16)
    draw.rounded_rectangle(
        [margin, margin, s - margin - 1, s - margin - 1],
        radius=max(4, s // 5),
        fill=(18, 22, 38, 255),
        outline=(87, 97, 153, 180),
        width=max(1, s // 64)
    )
    
    # Waveform bars
    bar_w = max(2, s // 12)
    gap = max(2, s // 16)
    total_w = 5 * bar_w + 4 * gap
    start_x = (s - total_w) // 2
    heights = [0.35, 0.6, 0.85, 0.55, 0.4]
    
    for i, h in enumerate(heights):
        x = start_x + i * (bar_w + gap)
        bar_h = int(h * (s - 4 * margin))
        y_top = margin * 2 + (s - 4 * margin - bar_h) // 2
        y_bot = y_top + bar_h
        
        r = int(87 + (143 - 87) * i / 4)
        g = int(212 + (97 - 212) * i / 4)
        b = 255
        draw.rounded_rectangle(
            [x, y_top, x + bar_w - 1, y_bot],
            radius=max(1, bar_w // 3),
            fill=(r, g, b, 240)
        )
    
    img.save(f"{iconset}/icon_{s}x{s}.png")
    if s * 2 <= 1024:
        img2x = img.resize((s*2, s*2), Image.LANCZOS)
        img2x.save(f"{iconset}/icon_{s}x{s}@2x.png")

PYTHON
        iconutil -c icns "$iconset" -o "$output" 2>/dev/null
        rm -rf "$iconset"
        return 0
    fi
    return 1
}

create_placeholder_icon() {
    local output="$1"
    python3 -c "
import struct, sys
w, h = 32, 32
pixels = b''
for y in range(h):
    for x in range(w):
        pixels += bytes([10, 15, 31, 255])
icon_data = pixels
if len(icon_data) % 2: icon_data += b'\x00'
entry = b'ih32' + struct.pack('>I', len(icon_data) + 8) + icon_data
full = b'icns' + struct.pack('>I', len(entry) + 8) + entry
sys.stdout.buffer.write(full)
" > "$output" 2>/dev/null || touch "$output"
}

create_dmg_background() {
    local output="${1:-build/dmg_staging/.background/background.png}"
    
    if command -v python3 &>/dev/null && python3 -c "from PIL import Image, ImageDraw" 2>/dev/null; then
        python3 - <<PYTHON
from PIL import Image, ImageDraw
import os

output = "$output"
w, h = 660, 400
img = Image.new('RGBA', (w, h), (12, 16, 32, 255))
draw = ImageDraw.Draw(img)

# Subtle gradient
for y in range(h):
    alpha = int(30 * (y / h))
    draw.line([(0, y), (w, y)], fill=(87, 97, 153, alpha))

# Hint text
draw.text((w//2 - 120, h - 45), "Drag ChatFlow → Applications", fill=(140, 150, 180, 200))

os.makedirs(os.path.dirname(output), exist_ok=True)
img.save(output)
PYTHON
        return
    fi
}

# --- Clean ---
if [[ "$1" == "clean" ]]; then
    echo "🧹 Cleaning build artifacts..."
    rm -rf .build/release build
    swift package clean 2>/dev/null || true
    echo "✅ Clean."
    exit 0
fi

if [[ "$(uname)" != "Darwin" ]]; then
    echo "❌ This script must run on macOS."
    exit 1
fi

# --- Build ---
echo "🔨 Building ${APP_NAME} v${VERSION}..."

if [[ ! -f "$BINARY" ]]; then
    echo "📦 Compiling..."
    swift build -c release 2>&1 | tail -5
fi

if [[ ! -f "$BINARY" ]]; then
    echo "❌ Build failed."
    exit 1
fi

# --- .app Bundle ---
echo "🏗️  Creating .app bundle..."

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUM}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>ChatFlow needs microphone access for voice dictation.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>ChatFlow needs accessibility access for global hotkey and text injection.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Copy entitlements
if [[ -f "Flow.entitlements" ]]; then
    cp "Flow.entitlements" "$APP_BUNDLE/Contents/Resources/entitlements.plist"
fi

# Create icon
echo "🎨 Creating app icon..."
create_app_icon "$APP_BUNDLE/Contents/Resources/AppIcon.icns" 2>/dev/null || \
    create_placeholder_icon "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

# Code sign with entitlements
# NOTE: Ad-hoc sign ("-") works without Apple Developer account.
# Hardened runtime (--options runtime) requires a paid certificate, so we skip it.
# Users won't see Gatekeeper warnings with ad-hoc signing + entitlements.
echo "🔐 Code signing with entitlements..."
if [[ -f "Flow.entitlements" ]]; then
    codesign --force --deep --sign - --entitlements Flow.entitlements "$APP_BUNDLE" 2>/dev/null || {
        echo "⚠️  Code signing failed. Users may need: xattr -cr $APP_BUNDLE"
    }
else
    codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || true
fi

APP_SIZE=$(du -sh "$APP_BUNDLE" | cut -f1)
echo "✅ .app bundle: $APP_BUNDLE ($APP_SIZE)"

# --- DMG (optional) ---
if [[ "$1" == "dmg" ]]; then
    echo ""
    echo "💿 Creating DMG installer..."
    
    DMG_DIR="build/dmg_staging"
    DMG_OUTPUT="build/${APP_NAME}.dmg"
    
    rm -rf "$DMG_DIR" "$DMG_OUTPUT"
    mkdir -p "$DMG_DIR"
    
    cp -r "$APP_BUNDLE" "$DMG_DIR/${APP_NAME}.app"
    ln -s /Applications "$DMG_DIR/Applications"
    
    # Background image
    mkdir -p "$DMG_DIR/.background"
    create_dmg_background "$DMG_DIR/.background/background.png"
    
    hdiutil create \
        -volname "$APP_NAME" \
        -srcfolder "$DMG_DIR" \
        -ov \
        -format UDZO \
        -imagekey zlib-level=9 \
        "$DMG_OUTPUT"
    
    rm -rf "$DMG_DIR"
    
    DMG_SIZE=$(du -sh "$DMG_OUTPUT" | cut -f1)
    echo "✅ DMG: $DMG_OUTPUT ($DMG_SIZE)"
fi

# --- Summary ---
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ${APP_NAME} v${VERSION}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  Install locally:"
echo "    cp -r $APP_BUNDLE /Applications/"
echo ""
if [[ "$1" == "dmg" ]]; then
echo "  DMG ready to distribute:"
echo "    build/${APP_NAME}.dmg"
echo ""
fi
echo "  First launch: right-click → Open to bypass Gatekeeper"
echo "  Or run: xattr -cr /Applications/ChatFlow.app"
echo ""
