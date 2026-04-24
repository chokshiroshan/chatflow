#!/bin/bash
# closeloop_vision.sh — Build+Run+Screenshot+Vision Analysis for ChatFlow
# Usage: ./scripts/closeloop_vision.sh [prompt]
#
# Reads secrets from environment or /etc/closeloop/env.
# Compresses screenshots automatically for reliable vision model analysis.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SCREENSHOT_DIR="$PROJECT_DIR/build_screenshots"
mkdir -p "$SCREENSHOT_DIR"

# Read secrets from env file if not already set
if [ -z "$CLOSELOOP_POOL_SECRET" ] && [ -f /etc/closeloop/env ]; then
    source /etc/closeloop/env
fi
if [ -z "$CLOSELOOP_DISPATCHER_URL" ]; then
    export CLOSELOOP_DISPATCHER_URL=http://localhost:8765
fi

if [ -z "$CLOSELOOP_POOL_SECRET" ]; then
    echo "error: set CLOSELOOP_POOL_SECRET (or create /etc/closeloop/env)"
    exit 1
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "🔨 Building & running ChatFlow on Mac Mini..."
RESULT=$(closeloop-build \
  --repo chatflow \
  --ref main \
  --scheme Flow \
  --path "$PROJECT_DIR" \
  --run \
  --env FLOW_HEADLESS=1 \
  --screenshot-delay-s 3 \
  --run-timeout-s 10 \
  2>&1)

echo "$RESULT"

# Extract screenshot URL
SCREENSHOT_URL=$(echo "$RESULT" | grep -oP 'screenshot: \Khttp[^\s]+' | head -1)

if [ -z "$SCREENSHOT_URL" ]; then
    echo "❌ No screenshot captured"
    echo "$RESULT"
    exit 1
fi

echo "📸 Downloading screenshot..."
RAW_FILE="$SCREENSHOT_DIR/${TIMESTAMP}_raw.png"
curl -s -o "$RAW_FILE" "$SCREENSHOT_URL"
echo "   Raw: $(du -h "$RAW_FILE" | cut -f1)"

# Compress for vision analysis
python3 -c "
from PIL import Image
import sys
img = Image.open('$RAW_FILE').convert('RGB')
# Resize to 1920 width max, maintaining aspect ratio
w, h = img.size
if w > 1920:
    ratio = 1920 / w
    img = img.resize((1920, int(h * ratio)), Image.LANCZOS)
img.save('$SCREENSHOT_DIR/${TIMESTAMP}.jpg', 'JPEG', quality=85)
import os
print(f'   Compressed: {os.path.getsize(\"$SCREENSHOT_DIR/${TIMESTAMP}.jpg\") / 1024:.0f} KB ({img.size[0]}x{img.size[1]})')
"

COMPRESSED="$SCREENSHOT_DIR/${TIMESTAMP}.jpg"
echo ""
echo "✅ Screenshot ready: $COMPRESSED"
echo ""
echo "To analyze with vision: use the 'image' tool on this file"
echo "  Path: $COMPRESSED"
