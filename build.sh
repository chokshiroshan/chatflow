#!/bin/bash
set -e

echo "🎤 ChatFlow — Voice-to-text for macOS"
echo "   Powered by your ChatGPT plan via OpenAI's Realtime API"
echo ""

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

if [[ "$(uname)" != "Darwin" ]]; then
    echo "❌ ChatFlow requires macOS 14+ (Sonoma or later)."
    echo "   Transfer this project to your Mac to build."
    exit 1
fi

if ! command -v swift &> /dev/null; then
    echo "❌ Swift not found. Install Xcode from the App Store or:"
    echo "   xcode-select --install"
    exit 1
fi

# Build release binary
echo "📦 Building..."
swift build -c release 2>&1 | tail -3

BINARY=".build/release/Flow"

if [[ ! -f "$BINARY" ]]; then
    echo "❌ Build failed — binary not found at $BINARY"
    exit 1
fi

echo ""
echo "✅ Build complete!"
echo ""
echo "To create a distributable .app bundle, run:"
echo "  ./build_app.sh"
echo ""
echo "To run directly:"
echo "  $BINARY"
echo ""
echo "First time setup:"
echo "  1. Run ChatFlow"
echo "  2. Sign in with your ChatGPT account"
echo "  3. Grant Accessibility + Microphone + Input Monitoring permissions"
echo "  4. Press your shortcut key (default: Ctrl+Space) to dictate"
echo ""
echo "Config:  ~/.flow/config.json"
echo "Auth:    ~/.flow/auth.json"
echo "Context: ~/.flow/context.md"
