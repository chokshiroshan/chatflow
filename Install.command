#!/bin/bash
# ChatFlow Installer
# Double-click this file to install ChatFlow and bypass Gatekeeper.

# Move to the directory containing this script
cd "$(dirname "$0")"

echo "🎤 ChatFlow Installer"
echo "━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if ChatFlow.app is in the same directory
if [ ! -d "ChatFlow.app" ]; then
    echo "❌ ChatFlow.app not found next to this installer."
    echo "   Make sure Install.command and ChatFlow.app are in the same folder."
    read -p "Press Enter to close..."
    exit 1
fi

# Copy to Applications
echo "📦 Copying ChatFlow to Applications..."
cp -r ChatFlow.app /Applications/ChatFlow.app 2>/dev/null

if [ $? -ne 0 ]; then
    echo "🔐 Need admin access to copy to Applications..."
    osascript -e 'do shell script "cp -r '"$(pwd)"'/ChatFlow.app /Applications/ChatFlow.app" with administrator privileges'
fi

# Remove quarantine flag (bypasses Gatekeeper)
echo "🔓 Removing Gatekeeper quarantine..."
xattr -cr /Applications/ChatFlow.app 2>/dev/null

echo ""
echo "✅ ChatFlow installed successfully!"
echo ""
echo "ChatFlow is now in your Applications folder."
echo "It will appear in your menu bar — no dock icon."
echo ""
echo "Hold Ctrl+Space anywhere to start dictating."
echo ""

# Open the app
echo "🚀 Launching ChatFlow..."
open /Applications/ChatFlow.app

sleep 1
