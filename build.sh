#!/bin/bash
set -e

echo "🎤 Flow — Voice Dictation + Voice Chat"
echo "   Powered by ChatGPT's Realtime API (included with your subscription)"
echo ""

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

if [[ "$(uname)" != "Darwin" ]]; then
    echo "❌ Flow requires macOS 14+ (Sonoma or later)."
    echo "   Transfer this project to your Mac to build."
    exit 1
fi

if ! command -v swift &> /dev/null; then
    echo "❌ Swift not found. Install Xcode from the App Store or:"
    echo "   xcode-select --install"
    exit 1
fi

echo "📦 Building..."
swift build -c release 2>&1 | tail -3

echo ""
echo "✅ Build complete!"
echo ""
echo "First time setup:"
echo "  1. Run: .build/release/Flow"
echo "  2. Sign in with your ChatGPT account"
echo "  3. Grant Accessibility + Microphone permissions"
echo "  4. Press Fn key to dictate, or use Voice Chat from the menu"
echo ""
echo "Configs stored in: ~/.flow/config.json"
echo "Tokens stored in:  macOS Keychain (ai.flow.app)"
