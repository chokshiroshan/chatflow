#!/bin/bash
set -e

# ChatFlow .app Bundle Builder
# Creates a proper macOS .app bundle from the Swift binary.
# Run on macOS 14+ after `swift build -c release`.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

APP_NAME="ChatFlow"
BUNDLE_ID="ai.flow.app"
BINARY=".build/release/Flow"
APP_BUNDLE="build/${APP_NAME}.app"

if [[ "$(uname)" != "Darwin" ]]; then
    echo "❌ This script must run on macOS."
    exit 1
fi

if [[ ! -f "$BINARY" ]]; then
    echo "📦 Binary not found. Building first..."
    swift build -c release 2>&1 | tail -3
fi

if [[ ! -f "$BINARY" ]]; then
    echo "❌ Build failed."
    exit 1
fi

echo "🏗️  Creating .app bundle..."

# Clean previous build
rm -rf "$APP_BUNDLE"

# Create bundle structure
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy binary
cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Create Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>ChatFlow</string>
    <key>CFBundleDisplayName</key>
    <string>ChatFlow</string>
    <key>CFBundleIdentifier</key>
    <string>ai.flow.app</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>ChatFlow</string>
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

# Create PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Copy entitlements into bundle for reference
if [[ -f "Flow.entitlements" ]]; then
    cp "Flow.entitlements" "$APP_BUNDLE/Contents/Resources/entitlements.plist"
fi

# Create app icon using macOS built-in tools
echo "🎨 Creating app icon..."
create_app_icon "$APP_BUNDLE/Contents/Resources/AppIcon.icns" 2>/dev/null || create_placeholder_icon "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

# Ad-hoc code sign (required for macOS to not block the app)
echo "🔐 Code signing..."
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || {
    echo "⚠️  Code signing failed. The app will still work but users may need to"
    echo "   right-click → Open on first launch to bypass Gatekeeper."
}

# Calculate size
SIZE=$(du -sh "$APP_BUNDLE" | cut -f1)

echo ""
echo "✅ Created: $APP_BUNDLE ($SIZE)"
echo ""
echo "To install:"
echo "  cp -r $APP_BUNDLE /Applications/"
echo ""
echo "To share with testers:"
echo "  zip -r ChatFlow.zip $APP_BUNDLE"
echo "  # Or create a DMG:"
echo "  hdiutil create -volname ChatFlow -srcfolder $APP_BUNDLE -ov -format UDZO ChatFlow.dmg"
echo ""
echo "⚠️  First launch: users must right-click → Open to bypass Gatekeeper."
echo "   Permissions needed: Microphone, Accessibility, Input Monitoring"
echo ""

# --- Icon creation helpers ---

create_app_icon() {
    local output="$1"
    # Use sips to create icns from a generated PNG
    local iconset="/tmp/chatflow.iconset"
    rm -rf "$iconset"
    mkdir -p "$iconset"
    
    # Generate a simple icon using Python + PIL if available
    if command -v python3 &>/dev/null && python3 -c "from PIL import Image, ImageDraw" 2>/dev/null; then
        python3 - <<'PYTHON'
from PIL import Image, ImageDraw
import os

iconset = "/tmp/chatflow.iconset"
sizes = [16, 32, 64, 128, 256, 512]

for s in sizes:
    img = Image.new('RGBA', (s, s), (10, 15, 31, 255))
    draw = ImageDraw.Draw(img)
    
    # Rounded rectangle background with gradient-like effect
    margin = max(2, s // 16)
    draw.rounded_rectangle(
        [margin, margin, s - margin - 1, s - margin - 1],
        radius=max(4, s // 5),
        fill=(18, 22, 38, 255),
        outline=(87, 97, 153, 180),
        width=max(1, s // 64)
    )
    
    # Draw a simple waveform (3 bars)
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
        
        # Cyan to purple gradient approximation
        r = int(87 + (143 - 87) * i / 4)
        g = int(212 + (97 - 212) * i / 4)
        b = int(255)
        draw.rounded_rectangle(
            [x, y_top, x + bar_w - 1, y_bot],
            radius=max(1, bar_w // 3),
            fill=(r, g, b, 240)
        )
    
    # Save for both normal and @2x
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
    # Create a minimal valid icns file (32x32 dark blue square)
    # This is a fallback — the app will work but with a default icon
    python3 -c "
import struct, sys
# Minimal 32x32 RGBA icon
w, h = 32, 32
pixels = b''
for y in range(h):
    for x in range(w):
        # Dark navy background
        pixels += bytes([10, 15, 31, 255])
# icns format: type(4) + size(4) + data
# ih32 type = 0x69683332
icon_data = pixels
# Pad to even
if len(icon_data) % 2: icon_data += b'\x00'
entry = b'ih32' + struct.pack('>I', len(icon_data) + 8) + icon_data
full = b'icns' + struct.pack('>I', len(entry) + 8) + entry
sys.stdout.buffer.write(full)
" > "$output" 2>/dev/null || touch "$output"
}
